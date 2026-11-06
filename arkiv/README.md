# Dhaniverse on Arkiv

Dhaniverse is a multiplayer town game where the only money is USDC. Arkiv holds the town's **public,
queryable, expiring** record: the Bounty Board's sponsor campaigns, each day's Market Rush board, the
food price history, player profiles and the morning paper's index. Swarm holds the content those
entries point to (campaign story/media bundles, the paper's text, season snapshots).

- Runs on Arkiv's current testnet, **Rabdi** (chain id `7794095`,
  RPC `https://rpc.rabdi.db-chain.testnet.arkiv.network`, explorer <https://rabdi.explorer.arkiv.network>),
  with `@arkiv-network/sdk@1.0.1`.
- Code: [`services/publisher`](../services/publisher) (writes, and the read API the game and website use).
- User-visible feature reading from Arkiv: the **Bounty Board** in the town square. The game server's
  `GET /arkiv/campaigns` proxies the publisher's `GET /campaigns`, a live `arkiv_query`; the website's
  boards, price chart, profiles and paper archive read the same way.

## Writer wallet

| Role | Address |
|---|---|
| Publisher (owner of every Dhaniverse entity) | [`0x584A19Fd7AbDe7aa89aE759CE4b8E018901eeF97`](https://rabdi.explorer.arkiv.network/address/0x584A19Fd7AbDe7aa89aE759CE4b8E018901eeF97) |

Entities are written with `env = "live"` for the live run.

## A query you can run

No key needed:

```sh
curl -s https://rpc.rabdi.db-chain.testnet.arkiv.network -H 'content-type: application/json' -d '{
  "jsonrpc":"2.0","id":1,"method":"arkiv_query",
  "params":["arkiv.schema = str('\''dhaniverse.campaign.v1'\'') AND env = str('\''live'\'') AND status = str('\''live'\'') AND $owner = addr(0x584A19Fd7AbDe7aa89aE759CE4b8E018901eeF97)",
            {"select":{"key":true,"owner":true,"expiresAt":true,"attributes":true},"limit":"0x64"}]}'
```

Or with the SDK, every query the game and website use:

```sh
cd services/publisher && npm ci && npm run query -- 0x584A19Fd7AbDe7aa89aE759CE4b8E018901eeF97 live
```

## Files

| File | |
|---|---|
| [schema.md](schema.md) | entities, attributes, which are queried, owners, expiration |
| [how-you-use-arkiv.md](how-you-use-arkiv.md) | the data flow, the writes, the reads, the code |
| [why-arkiv.md](why-arkiv.md) | why this data is on Arkiv, and what is deliberately not |
| [reach.md](reach.md) | who sees it |
| [friction.md](friction.md) | honest feedback on the SDK and docs |
| [swarm.md](swarm.md) | the Arkiv + Swarm split, references, postage batch, upload and read steps |

The publisher is MIT licensed (`services/publisher/LICENSE`).
