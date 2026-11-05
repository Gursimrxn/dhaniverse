//! Sponsors' campaigns, as CampaignEscrow reported them. Each is a Bounty Board card while it's live and has slots:
//! the quest's energy and payout come from the campaign, and a slot is held for a player from taking the quest until
//! their claim is paid, so a finished quest always has its money.

use crate::{book::TEMPLATES, Usdc};
use serde::Serialize;
use std::collections::BTreeMap;

const DAY_S: u64 = 86_400;

/// `kind` on chain: 0 Sponsored, 1 Boosted.
pub const BOOSTED: u8 = 1;

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Campaign {
    pub id: u64,
    pub sponsor: String,
    pub template: String,
    /// The Swarm reference of its story and media.
    pub meta_hash: String,
    pub budget: Usdc,
    pub payout: Usdc,
    pub energy: u32,
    pub max_claims: u32,
    pub per_human_cap: u16,
    pub start: u64,
    pub end: u64,
    pub kind: u8,
    pub deliver_to: String,
    /// Claims paid, and the budget they and the advances used.
    pub claims: u32,
    pub spent: Usdc,
    /// Slots held by players on its quest, or with a claim on its way.
    pub held: u32,
    /// Players paid a claim, for the sponsor's count of people reached.
    pub humans: std::collections::BTreeSet<String>,
    /// Paused, cancelled or refunded: no new claims.
    pub closed: bool,
}

impl Campaign {
    pub fn boosted(&self) -> bool {
        self.kind == BOOSTED
    }

    pub fn slots_left(&self) -> u32 {
        self.max_claims.saturating_sub(self.claims + self.held)
    }

    pub fn remaining(&self) -> Usdc {
        self.budget.saturating_sub(self.spent)
    }

    /// Open for new players at this chain time (unix seconds; 0 when the chain hasn't said).
    pub fn live(&self, time: u64) -> bool {
        let in_window = time == 0 || (self.start <= time && time < self.end);
        !self.closed && in_window && TEMPLATES.contains(&self.template.as_str())
    }

    /// CampaignEscrow's daily cap: what's left over the days left, at least a day.
    pub fn daily_cap(&self, time: u64) -> Usdc {
        let days_left = self.end.saturating_sub(time).div_ceil(DAY_S).max(1);
        self.remaining() / days_left
    }
}

#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Campaigns {
    map: BTreeMap<u64, Campaign>,
    /// The chain's time, from the latest block seen.
    pub time: u64,
}

impl Campaigns {
    pub fn get(&self, id: u64) -> Option<&Campaign> {
        self.map.get(&id)
    }

    pub(crate) fn get_mut(&mut self, id: u64) -> Option<&mut Campaign> {
        self.map.get_mut(&id)
    }

    pub(crate) fn add(&mut self, campaign: Campaign) -> bool {
        if self.map.contains_key(&campaign.id) {
            return false;
        }
        self.map.insert(campaign.id, campaign);
        true
    }

    pub fn all(&self) -> impl Iterator<Item = &Campaign> {
        self.map.values()
    }

    /// The Bounty Board: live sponsored campaigns with slots, by id.
    pub fn board(&self) -> impl Iterator<Item = &Campaign> {
        self.map
            .values()
            .filter(|c| !c.boosted() && c.live(self.time) && c.slots_left() > 0)
    }

    /// The first live boosted campaign with a slot, which sponsors today's mystery.
    pub fn booster(&self) -> Option<&Campaign> {
        self.map
            .values()
            .find(|c| c.boosted() && c.live(self.time) && c.slots_left() > 0)
    }

    /// Lets go of a held slot.
    pub(crate) fn release(&mut self, id: u64) {
        if let Some(c) = self.map.get_mut(&id) {
            c.held = c.held.saturating_sub(1);
        }
    }
}
