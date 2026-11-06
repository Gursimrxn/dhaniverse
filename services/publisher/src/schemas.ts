// The Arkiv schemas: the single source of truth for every entity Dhaniverse writes. `arkiv/schema.md`
// documents these; the contract test checks the two agree on the wire.
//
// Rules that shaped them (docs.arkiv.network/schemas/define, /reference/limits):
// - A named schema tags each entity with an indexed `arkiv.schema` attribute. The tag is not a
//   security boundary — anyone can write it — so every read also filters on the writer (`$owner`).
// - Only the columns we filter on are indexed (indexing costs gas on every write).
// - Strings are at most 128 bytes; bytes values at most 128 KiB; at most 31 columns per named schema.
// - u64 values must be written tagged (`u64(n)`); numbers default to i32.
// - Nothing private: no balances, no amounts anyone paid, no wallets of players.

import { bytes, defineSchema, i32, str, u64 } from "@arkiv-network/sdk/schema"

export const SCHEMA_VERSION = "v1"

/** A live sponsor campaign, as the Bounty Board shows it. Expires at the campaign's end. */
export const CampaignSchema = defineSchema("dhaniverse.campaign.v1", {
  env: str().indexed(),
  campaignId: u64().indexed(),
  status: str().indexed(),
  template: str().indexed(),
  sponsor: str().indexed(),
  title: str(),
  /** USDC base units paid per completed claim: the sponsor's public offer. */
  payout: u64(),
  energy: i32(),
  slotsLeft: i32().indexed(),
  /** Unix seconds. */
  endsAt: u64().indexed(),
  /** Swarm reference (64 hex) of the story/media bundle; the same 32 bytes as the on-chain metaHash. */
  metaHash: str().optional(),
  /** Content fingerprint, so a restarted publisher can tell an unchanged card from a stale one. */
  fp: str(),
})

/** A closed day's Rush board: rank, name and title only (the server never publishes scores). 48 h. */
export const RushBoardSchema = defineSchema("dhaniverse.rush_board.v1", {
  env: str().indexed(),
  day: u64().indexed(),
  season: i32().indexed().optional(),
  /** Which server board this came from (`rush_today` when the server has a daily board, else `rush`). */
  board: str(),
  leader: str().optional(),
  entries: i32(),
  /** JSON: [{rank, name, title}]. */
  top: bytes(),
})

/** Five minutes of the FOOD price, one entity per batch. 7 days. */
export const PriceTickSchema = defineSchema("dhaniverse.price_tick.v1", {
  env: str().indexed(),
  /** Unix seconds, window start (inclusive) and end (exclusive). */
  startTs: u64().indexed(),
  endTs: u64().indexed(),
  day: u64().indexed(),
  /** USDC base units per FOOD. */
  open: u64(),
  high: u64(),
  low: u64(),
  close: u64(),
  samples: i32(),
  /** JSON: [[unixSeconds, price], …], only the samples where the price moved plus the first and last. */
  series: bytes(),
  shock: str().optional(),
})

/** A player's public face: name, title, stamps, ENS name. Expires at season end; renewed. */
export const ProfileSchema = defineSchema("dhaniverse.profile.v1", {
  env: str().indexed(),
  name: str().indexed(),
  season: i32().indexed().optional(),
  title: str(),
  /** Comma list of earned stamps. */
  stamps: str(),
  ens: str().optional(),
  fp: str(),
})

/** The morning paper's index entry. The body lives on Swarm (`bodyRef`); inline only if Swarm is off. 30 days. */
export const PaperSchema = defineSchema("dhaniverse.paper.v1", {
  env: str().indexed(),
  day: u64().indexed(),
  headline: str(),
  stories: i32(),
  bodyRef: str().optional(),
  /** JSON {headline, stories}; present only when the body could not go to Swarm. */
  body: bytes().optional(),
})

/** A finished season: the reference of its snapshot on Swarm. Written only when Swarm is configured. */
export const SeasonSchema = defineSchema("dhaniverse.season.v1", {
  env: str().indexed(),
  season: i32().indexed(),
  endedDay: u64(),
  snapshotRef: str(),
})

/** One per town: the save's first line (seed, rules, quest book, chain mode), encrypted. 180 days, renewed. */
export const CitySchema = defineSchema("dhaniverse.city.v1", {
  env: str().indexed(),
  townId: str().indexed(),
  chain: str(),
  rulesHash: str(),
  startedAt: u64(),
  /** nonce (12) + AES-256-GCM ciphertext + tag (16) of the setup line. */
  payload: bytes(),
})

/** One per batch of save lines: gzipped JSONL, encrypted, hash-chained. 180 days, renewed. */
export const LogSchema = defineSchema("dhaniverse.log.v1", {
  env: str().indexed(),
  townId: str().indexed(),
  fromSeq: u64().indexed(),
  toSeq: u64().indexed(),
  /** SHA-256 hex of the previous batch's plaintext JSONL (64 zeros for the first). */
  prevHash: str(),
  /** SHA-256 hex of this batch's plaintext JSONL. */
  hash: str(),
  /** nonce (12) + AES-256-GCM(gzip(JSONL)) + tag (16). */
  payload: bytes(),
})


// ---- the town in public, derived from the save's events (src/town.ts) ---------------------------
// Names, titles, stamps and outcome kinds only: never a balance, an amount a player was paid, a wallet or anything
// from World ID. The pool is the house pool's own books, not any player's money.

/** One feed post, as the server's feed wrote it (its words never hold an amount). 7 days from the post. */
export const FeedSchema = defineSchema("dhaniverse.feed.v1", {
  env: str().indexed(),
  /** The server's post id: unique in the town. */
  postId: u64().indexed(),
  /** Real day (the rules' `real_day`). */
  day: u64().indexed(),
  kind: str().indexed(),
  /** The player the post is about, if any. */
  actor: str().optional(),
  /** Unix seconds. */
  at: u64(),
  /** JSON: [{id, text}]. */
  items: bytes(),
})

/** One chest opening: the public record that every draw followed the odds plate and the pity rule. 30 days. */
export const ChestSchema = defineSchema("dhaniverse.chest.v1", {
  env: str().indexed(),
  day: u64().indexed(),
  player: str().indexed(),
  /** The save line it happened on: unique in the town. */
  seq: u64().indexed(),
  /** `daily` or `weekly`. */
  kind: str(),
  /** `wood`, `brass` or `gold`. */
  tier: str(),
  /** Daily chests opened since the last golden drop, before this one (the pity rule's counter). */
  pityBefore: i32(),
  /** The headline kind, never an amount: `golden_drop`, `voucher` or `plain`. */
  outcome: str().indexed(),
  /** This player's daily chest number (1, 2, …): the draw's index in the rules' dice. */
  draw: i32(),
  /** JSON {energy, tickets, voucher, golden_drop (true/false, never the amount), pity}. */
  contents: bytes(),
  at: u64(),
})

/** A stamp (from a quest) or a first (first meal, first quest, Town Pass) earned. Until the season's end. */
export const StampSchema = defineSchema("dhaniverse.stamp.v1", {
  env: str().indexed(),
  player: str().indexed(),
  stamp: str().indexed(),
  /** `stamp` or `first`. Skill-game medals join as `medal` when the game layer emits them. */
  kind: str().indexed(),
  /** `kind:player:stamp`: each is earned once. */
  ref: str().indexed(),
  day: u64(),
  at: u64(),
  seq: u64(),
})

/** A player's login streak. Renewed on each login day; when it expires (8 days) the streak is broken. */
export const StreakSchema = defineSchema("dhaniverse.streak.v1", {
  env: str().indexed(),
  player: str().indexed(),
  /** Real days in a row. */
  streak: i32(),
  daysOfLast7: i32(),
  /** The daily chest's tier the streak earns: `wood`, `brass` or `gold`. */
  chestTier: str(),
  /** The real day of the last login. */
  day: u64(),
  fp: str(),
})

/** The house pool's statement for one closed real day: its own public books. 90 days. USDC base units. */
export const PoolSchema = defineSchema("dhaniverse.pool.v1", {
  env: str().indexed(),
  day: u64().indexed(),
  /** fixed + surprise + safety at the day's first reading, and at its last. */
  opening: u64(),
  closing: u64(),
  /** The day's payout budget across the three buckets. */
  budget: u64(),
  /** Paid out from each bucket, as the chain confirmed it. */
  spentFixed: u64(),
  spentSurprise: u64(),
  spentSafety: u64(),
  /** closing - opening + spent: what came in (the treasury's split, top-ups). */
  inflow: u64(),
})

export const SCHEMAS = {
  campaign: CampaignSchema,
  rush_board: RushBoardSchema,
  price_tick: PriceTickSchema,
  profile: ProfileSchema,
  paper: PaperSchema,
  season: SeasonSchema,
  feed: FeedSchema,
  chest: ChestSchema,
  stamp: StampSchema,
  streak: StreakSchema,
  pool: PoolSchema,
} as const

export type EntityType = keyof typeof SCHEMAS

/** The save's two entity types. They are written by the save mirror (`save.ts`), not tracked in the publisher's state. */
export const SAVE_SCHEMAS = { city: CitySchema, log: LogSchema } as const
export type SaveType = keyof typeof SAVE_SCHEMAS
export const ALL_SCHEMAS = { ...SCHEMAS, ...SAVE_SCHEMAS } as const
export type DraftType = EntityType | SaveType
export const isSaveType = (t: DraftType): t is SaveType => t === "city" || t === "log"
