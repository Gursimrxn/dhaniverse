# Reach

Who sees the data Dhaniverse puts on Arkiv, and where. Numbers are left blank until we have measured
them; nothing here is an estimate dressed up as a metric.

## Where Arkiv data is shown

| Surface | Who | What they read from Arkiv |
|---|---|---|
| **Bounty Board** in the town square (in game) | every player who walks past it | live sponsor campaign cards (`dhaniverse.campaign.v1`) |
| Phone "Boards" history (in game) | players | yesterday's and today's Rush boards (`dhaniverse.rush_board.v1`) |
| Town website | anyone with the link, no account | Rush boards, the food price chart (`price_tick`), profiles, the paper archive |
| Sponsor console | sponsors | their campaign's card as players see it |
| Anyone with `curl` | other builders | the same entities, by `arkiv_query`, owner-filtered |

The game client never talks to Arkiv directly: the server's `GET /arkiv/campaigns` proxies the
publisher's read API, which queries Arkiv live. One query per 10 seconds serves every player (the
cache), so player count doesn't multiply load on Arkiv's RPC.

## Who the data is for

- **Players**, who choose quests from the Bounty Board and check boards and prices.
- **Sponsors**, who pay USDC for players to do real on-chain actions (a Uniswap swap, an ENS record)
  and want to see their card live and see it vanish when their campaign ends.
- **Anyone curious about the town**, who can read its public record without trusting our server.

## Measured during the event

To be filled in after the live run, from the game server's logs, the publisher's `/health` and Arkiv
itself. Every row stays blank until it is measured.

| Measure | Value | Source |
|---|---|---|
| Players who joined during the event | _not measured yet_ | game server log |
| Players who opened the Bounty Board | _not measured yet_ | game server log |
| Bounty Board reads served (server → publisher) | _not measured yet_ | publisher `/health` → `reads.requests["/campaigns"]` |
| Arkiv queries sent by the read API (cache misses) | _not measured yet_ | publisher `/health` → `reads.arkivQueries` |
| Website visits | _not measured yet_ | — |
| Entities written, by type | _not measured yet_ | `npm run query -- WRITER live` / publisher `/health` |
| Campaigns published | _not measured yet_ | Arkiv |
