//! The JSON-RPC connection and the typed reads built on it.

use crate::bindings::{
    ICampaignEscrow, IEnsRegistry, IPermit2, IV4Quoter, IVerifiableFactory, PoolKey,
    QuoteExactSingleParams, IERC20,
};
use crate::plan::Reads;
use crate::revert::ErrorBook;
use alloy::network::TransactionBuilder;
use alloy::primitives::{Address, Bytes, U256};
use alloy::providers::{DynProvider, Provider, RootProvider};
use alloy::rpc::types::TransactionRequest;
use alloy::sol_types::SolCall;
use std::sync::Arc;

/// Opens an HTTP JSON-RPC connection (no fillers: the executor manages nonces, gas and fees itself).
pub fn connect(url: &str) -> Result<DynProvider, String> {
    let url = url
        .parse()
        .map_err(|_| "CHAIN_RPC_URL is not a valid URL".to_string())?;
    Ok(RootProvider::new_http(url).erased())
}

/// `eth_call` of a typed function, decoded.
pub async fn view<C: SolCall>(
    p: &DynProvider,
    errors: &ErrorBook,
    to: Address,
    call: C,
) -> Result<C::Return, String> {
    let req = TransactionRequest::default()
        .with_to(to)
        .with_input(Bytes::from(call.abi_encode()));
    let raw = p.call(req).await.map_err(|e| errors.explain(&e))?;
    C::abi_decode_returns(&raw)
        .map_err(|e| format!("{} returned something unexpected: {e}", C::SIGNATURE))
}

/// The planner's reads, answered from the chain.
pub struct ChainReads {
    pub provider: DynProvider,
    pub errors: Arc<ErrorBook>,
}

impl Reads for ChainReads {
    async fn erc20_allowance(
        &self,
        token: Address,
        owner: Address,
        spender: Address,
    ) -> Result<U256, String> {
        view(
            &self.provider,
            &self.errors,
            token,
            IERC20::allowanceCall { owner, spender },
        )
        .await
    }

    async fn erc20_balance(&self, token: Address, owner: Address) -> Result<U256, String> {
        view(
            &self.provider,
            &self.errors,
            token,
            IERC20::balanceOfCall { account: owner },
        )
        .await
    }

    async fn permit2_allowance(
        &self,
        permit2: Address,
        owner: Address,
        token: Address,
        spender: Address,
    ) -> Result<(U256, u64), String> {
        let r = view(
            &self.provider,
            &self.errors,
            permit2,
            IPermit2::allowanceCall {
                user: owner,
                token,
                spender,
            },
        )
        .await?;
        Ok((U256::from(r.amount), r.expiration.to::<u64>()))
    }

    async fn quote_exact_in(
        &self,
        quoter: Address,
        key: PoolKey,
        zero_for_one: bool,
        amount_in: u64,
    ) -> Result<U256, String> {
        let params = QuoteExactSingleParams {
            poolKey: key,
            zeroForOne: zero_for_one,
            exactAmount: amount_in as u128,
            hookData: Bytes::new(),
        };
        let r = view(
            &self.provider,
            &self.errors,
            quoter,
            IV4Quoter::quoteExactInputSingleCall { params },
        )
        .await
        .map_err(|e| format!("quote failed: {e}"))?;
        Ok(r.amountOut)
    }

    async fn campaign_quest_token(
        &self,
        escrow: Address,
        campaign: u64,
    ) -> Result<Address, String> {
        view(
            &self.provider,
            &self.errors,
            escrow,
            ICampaignEscrow::questTokenCall {
                campaignId: U256::from(campaign),
            },
        )
        .await
    }

    async fn predict_proxy(
        &self,
        factory: Address,
        deployer: Address,
        salt: U256,
    ) -> Result<Address, String> {
        view(
            &self.provider,
            &self.errors,
            factory,
            IVerifiableFactory::predictProxyAddressCall { deployer, salt },
        )
        .await
    }

    async fn has_code(&self, address: Address) -> Result<bool, String> {
        use alloy::providers::Provider;
        let code = self
            .provider
            .get_code_at(address)
            .await
            .map_err(|e| self.errors.explain(&e))?;
        Ok(!code.is_empty())
    }

    async fn ens_resolver(&self, registry: Address, label: &str) -> Result<Address, String> {
        view(
            &self.provider,
            &self.errors,
            registry,
            IEnsRegistry::getResolverCall {
                label: label.into(),
            },
        )
        .await
    }

    async fn ens_owner(&self, registry: Address, label: &str) -> Result<Address, String> {
        // An unregistered or expired label has no owner; some registries revert instead of returning zero.
        let id = match view(
            &self.provider,
            &self.errors,
            registry,
            IEnsRegistry::findTokenIdCall {
                label: label.into(),
            },
        )
        .await
        {
            Ok(id) => id,
            Err(_) => return Ok(Address::ZERO),
        };
        Ok(view(
            &self.provider,
            &self.errors,
            registry,
            IEnsRegistry::ownerOfCall { tokenId: id },
        )
        .await
        .unwrap_or(Address::ZERO))
    }
}
