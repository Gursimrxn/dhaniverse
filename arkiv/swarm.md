# Arkiv + Swarm

Arkiv holds the **index**: small, typed, queryable, expiring entities. Swarm holds the **content**:
immutable files addressed by the hash of what they contain. An Arkiv entity carries a Swarm reference;
the reference is all anyone needs to fetch and verify the content.

## The split

| Content | On Swarm | On Arkiv | Also on chain |
|---|---|---|---|
| Campaign story + images | a collection: `index.json` + `image-N.{png,jpg,webp,gif}` | `dhaniverse.campaign.v1.metaHash` = the collection's reference | `CampaignEscrow` `CampaignParams.metaHash` (bytes32) = the same 32 bytes |
| The morning paper | `paper-<day>.json` (headline + every story) | `dhaniverse.paper.v1.bodyRef`, plus `day`, `headline`, `stories` for listing | — |
| A finished season | `season-<n>.json` (final Rush board, people with titles and stamps) | `dhaniverse.season.v1.snapshotRef` | — |

What decides the side: anything a query filters or sorts on, or that should expire, is an Arkiv
attribute. Anything long, binary, or worth keeping past the entity's lifetime is Swarm content. A
paper's index entry expires after 30 days; its text stays on Swarm for as long as the postage batch
pays for it.

## Entity references

- A Swarm reference here is always a **plain 32-byte address** (64 hex characters). It fits a
  Solidity `bytes32` exactly, which is why the sponsor console can write the bundle's reference as the
  campaign's on-chain `metaHash` and the Arkiv card can carry the same value: chain, Arkiv and Swarm
  agree on one hash.
- Stored on Arkiv as a `str` attribute, lowercase hex without `0x` (`metaHash`, `bodyRef`,
  `snapshotRef`); the read API returns it as `swarm`, `body_ref`, `snapshot_ref`.
- **No key references on public entities.** Swarm's *encrypted* references are 64 bytes: the address
  plus the decryption key. Putting one on a public Arkiv entity would publish the key. All Dhaniverse
  content is public, so we upload it unencrypted (no `swarm-encrypt` header), and one function
  ([`src/swarmRef.ts`](../services/publisher/src/swarmRef.ts) `publicSwarmRef`) is the gate every
  reference passes on its way to Arkiv: it accepts only 64-hex references and refuses 128-hex ones,
  including one that a Bee node might return or one a card on the server might carry. Tests cover both.
- Nothing private is uploaded: no balances, amounts paid, wallets or uploader details. Bundle story
  fields are whitelisted; images are checked by their bytes; SVG is refused.

## Postage batch

Uploads are paid for by a postage batch on the Bee node the publisher talks to (`BEE_URL`,
`BEE_POSTAGE_BATCH`). **Not yet bought for this submission**: fill in after it exists. Read the values
from the node with `curl $BEE_URL/stamps/$BEE_POSTAGE_BATCH`, and the publisher logs them at start-up.

| Field | Value |
|---|---|
| Batch ID | `________________________________________________________________` ← _fill in_ |
| Depth / bucket depth | _fill in_ (`depth`, `bucketDepth`) |
| Amount (per chunk, PLUR) | _fill in_ (`amount`) |
| TTL at purchase | _fill in_ (`batchTTL`, seconds) |
| Immutable | _fill in_ (`immutableFlag`) |
| Bee node | _fill in_ (version, light/full, network) |

What we need from it: campaign bundles (≤ 4 MiB of images + a ≤ 32 KiB story each), one paper a city
day (a few KB), one snapshot a season (tens of KB). A small batch is ample; buy one with a TTL that
covers the event and well beyond. `GET /stamps/{id}`'s `utilizationRatio` says how full it is.

## Upload and read, step by step

### With the publisher (what the game and console use)

```sh
# Bee node running, batch bought and usable (GET /stamps/<id> → "usable": true)
export BEE_URL=http://localhost:1633 BEE_POSTAGE_BATCH=<batch id>
cd services/publisher && npm start

# sponsor console: story + images → reference and metaHash
curl -s -X POST http://127.0.0.1:8787/swarm/campaign-bundle \
  -F 'story={"title":"The Spice Run","sponsor":"Mango Traders","template":"spice_run","story":"Bring the saffron home."}' \
  -F 'image=@cover.png;type=image/png'
# → {"reference":"<64 hex>","metaHash":"0x<64 hex>","index":"/bzz/<ref>/","files":[…],…}

# read it back through the publisher (from its Bee node)
curl -s http://127.0.0.1:8787/swarm/campaign-bundle/<reference>
```

The publisher uploads the paper and season snapshots itself when it sees them, then writes the Arkiv
entity with the reference.

### With Bee's HTTP API directly (what the publisher does)

From the Bee API (OpenAPI `Swarm.yaml`, API 8.x):

```sh
# one file → a manifest reference
curl -s -X POST "$BEE_URL/bzz?name=paper-41.json" \
  -H "swarm-postage-batch-id: $BEE_POSTAGE_BATCH" -H "swarm-pin: true" \
  -H "content-type: application/json" --data-binary @paper-41.json
# → {"reference":"<64 hex>"}

# a collection: multipart/form-data is always a collection; each part's filename becomes its path
# and its Content-Type is stored in the manifest (Bee pkg/api/dirs.go reads both from the part headers)
curl -s -X POST "$BEE_URL/bzz" \
  -H "swarm-postage-batch-id: $BEE_POSTAGE_BATCH" -H "swarm-collection: true" \
  -H "swarm-index-document: index.json" \
  -F 'file=@index.json;type=application/json' -F 'file=@image-1.png;type=image/png'

# read
curl -s "$BEE_URL/bzz/<reference>/"            # the index document (or the single file)
curl -s "$BEE_URL/bzz/<reference>/image-1.png"  # one file of a collection
```

### From an Arkiv entity to its content

```sh
# 1. find the card (or paper) on Arkiv: see README.md for the full query
#    → attributes include {"name":"metaHash","type":"str","value":"<64 hex>"}
# 2. fetch it from any Bee node or gateway
curl -s "$BEE_URL/bzz/<metaHash>/index.json"
# 3. optional: check the on-chain campaign's metaHash is 0x<the same 64 hex>
```

## What happens when Swarm isn't there

No fake references, ever. If `BEE_URL`/`BEE_POSTAGE_BATCH` aren't set, the publisher says so once,
bundle uploads answer 503, season snapshots are skipped, and the paper goes to Arkiv with its text
inline (`body`) instead of `bodyRef`. If Bee is set but failing, the paper waits for five tries with
backoff before going inline; a 402 from Bee is reported as a postage batch problem.
