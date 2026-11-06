# Why Arkiv

## The data that fits

Dhaniverse has a small set of facts that are **public**, that **people outside the game want to
query**, and that **should stop existing after a while**:

- **Sponsor campaigns on the Bounty Board.** A sponsor funds a quest on chain; players, the website
  and the sponsor all want to see the live cards. A card is meaningless after the campaign ends.
- **Each day's Market Rush board.** Interesting today and tomorrow, not next month.
- **The food price history.** A week of 5-minute batches feeds the market chart.
- **Player profiles.** Name, title, stamps, ENS name: public by design, and only worth keeping while the
  player plays this season.
- **The paper's index**, pointing at its text on Swarm.

For this data Arkiv gives us, in one place, what we would otherwise assemble from three systems:

1. **Queryable without running an indexer.** Attributes are indexed on write, and the website, the
   game and a judge with `curl` ask the same `arkiv_query`. We don't run a database or a subgraph for
   the public view.
2. **Expiry that matches the data's life.** A campaign card is created to expire at the campaign's end;
   boards in 48 h; price batches in 7 days; profiles at season end. Nothing to garbage-collect and no
   stale cards on the board, which is exactly the bug a cache would give us.
3. **Verifiable provenance.** Every entity is owned by our writer wallet, signed, on a chain. Anyone
   can filter `$owner` and know the board they see is the one Dhaniverse published, not a copy.
4. **Cheap enough to batch freely.** One transaction carries a whole flush (creates, patches,
   extensions), so a 5-minute price batch costs one entity, not one per sample.

## What we deliberately do not put on Arkiv

Arkiv is slower than the game: 2-second blocks, and a public RPC that is heavily rate limited. So:

- **Not the hot path.** The game's rules run in the server; money settles on Ethereum Sepolia. The
  game never waits for an Arkiv write; a sidecar writes in batches off its own timer, and if Arkiv is
  down the game doesn't notice.
- **Not the truth.** Balances, payouts and campaign budgets come from the chain and the server's log.
  Arkiv is a read model of what is already public.
- **Nothing private.** No balances, no amounts anyone was paid, no player wallets, nothing from World
  ID. Arkiv is public and permanent until expiry.
- **Not blobs.** Story and media bundles, the paper's text and season snapshots are content: they go
  to Swarm, addressed by hash, and the Arkiv entity carries the 32-byte reference
  ([swarm.md](swarm.md)).

## Why not the alternatives

- **Events on Sepolia + a subgraph:** the campaign *money* is on Sepolia already, but boards, prices and
  profiles are not chain events, and writing them there to index them later would cost real gas and
  give no expiry.
- **Our own database behind an API:** works, but the public would have to trust our server, and we'd
  write the expiry and the query layer ourselves.
- **Swarm alone:** great for content by hash, not for "every live card with slots left, soonest first".
