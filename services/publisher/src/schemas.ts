// The Arkiv schemas: the single source of truth for every entity Tallyport writes. `arkiv/schema.md`
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
export const CampaignSchema = defineSchema("tallyport.campaign.v1", {
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
export const RushBoardSchema = defineSchema("tallyport.rush_board.v1", {
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
export const PriceTickSchema = defineSchema("tallyport.price_tick.v1", {
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
export const ProfileSchema = defineSchema("tallyport.profile.v1", {
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
export const PaperSchema = defineSchema("tallyport.paper.v1", {
  env: str().indexed(),
  day: u64().indexed(),
  headline: str(),
  stories: i32(),
  bodyRef: str().optional(),
  /** JSON {headline, stories}; present only when the body could not go to Swarm. */
  body: bytes().optional(),
})

/** A finished season: the reference of its snapshot on Swarm. Written only when Swarm is configured. */
export const SeasonSchema = defineSchema("tallyport.season.v1", {
  env: str().indexed(),
  season: i32().indexed(),
  endedDay: u64(),
  snapshotRef: str(),
})

export const SCHEMAS = {
  campaign: CampaignSchema,
  rush_board: RushBoardSchema,
  price_tick: PriceTickSchema,
  profile: ProfileSchema,
  paper: PaperSchema,
  season: SeasonSchema,
} as const

export type EntityType = keyof typeof SCHEMAS
