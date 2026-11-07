//! Withdrawals: USDC leaves a player's wallet only to a real address that isn't theirs, never more than they hold, and
//! the town hears what the chain did.

mod common;

use common::{intents, World, USDC};
use rules::chain::{Intent, Observation};
use rules::{Command, Event, Refusal};

const SAM: &str = "sam";
const ELSEWHERE: &str = "0x1111111111111111111111111111111111111111";

fn withdraw(w: &mut World, to: &str, amount: u64) -> Result<Vec<Event>, Refusal> {
    let reference = w.fresh_ref();
    w.run(Command::Withdraw {
        account: SAM.into(),
        to: to.into(),
        amount,
        reference,
    })
}

#[test]
fn a_withdrawal_goes_to_the_chain_and_comes_back() {
    let mut w = World::new();
    w.fund(SAM, 3 * USDC);
    let events = withdraw(&mut w, ELSEWHERE, 2 * USDC).unwrap();
    assert!(events
        .iter()
        .any(|e| matches!(e, Event::WithdrawSent { amount, .. } if *amount == 2 * USDC)));
    let sent = intents(&events);
    let Some(Intent::Withdraw {
        player,
        to,
        amount,
        reference,
    }) = sent.first().cloned()
    else {
        panic!("no withdraw intent in {sent:?}");
    };
    assert_eq!((player.as_str(), to.as_str(), amount), (SAM, ELSEWHERE, 2 * USDC));
    let done = w
        .observe(Observation::Withdrawn {
            player,
            to,
            amount,
            reference: reference.clone(),
            tx: "0xabc".into(),
        })
        .unwrap();
    assert!(done.iter().any(|e| matches!(e, Event::Withdrawn { tx, .. } if tx == "0xabc")));
    // An answer for a ref already settled changes nothing.
    assert!(w
        .observe(Observation::Withdrawn {
            player: SAM.into(),
            to: ELSEWHERE.into(),
            amount: 2 * USDC,
            reference,
            tx: "0xabc".into(),
        })
        .is_err());
}

#[test]
fn a_withdrawal_needs_a_real_other_address_and_the_money() {
    let mut w = World::new();
    w.fund(SAM, USDC);
    assert_eq!(withdraw(&mut w, "not-an-address", 1), Err(Refusal::BadAddress));
    assert_eq!(withdraw(&mut w, "0x123", 1), Err(Refusal::BadAddress));
    let own = w.player(SAM).wallet.clone().unwrap();
    assert_eq!(withdraw(&mut w, &own, 1), Err(Refusal::BadAddress));
    assert_eq!(withdraw(&mut w, ELSEWHERE, 0), Err(Refusal::BadAmount));
    assert!(matches!(
        withdraw(&mut w, ELSEWHERE, 2 * USDC),
        Err(Refusal::NotEnoughUsdc { .. })
    ));
}

#[test]
fn a_refused_withdrawal_says_so() {
    let mut w = World::new();
    w.fund(SAM, USDC);
    let sent = intents(&withdraw(&mut w, ELSEWHERE, USDC).unwrap());
    let reference = sent[0].reference().unwrap().to_string();
    let failed = w
        .observe(Observation::IntentFailed {
            reference,
            reason: "ERC20InsufficientBalance".into(),
        })
        .unwrap();
    assert!(failed
        .iter()
        .any(|e| matches!(e, Event::WithdrawFailed { amount, .. } if *amount == USDC)));
}
