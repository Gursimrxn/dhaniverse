//! The loot crate (ux09): a meal bought with your own money drops an urgent crate at one of the town's spots, if none is
//! out, for anyone to reach first. It holds `PRIZE` for one claimer for `FOR_MS`; after that it's gone. Where it falls comes
//! from the meal's reference, so a replay drops the same crate in the same place. The prize is a house reward (the surprise
//! bucket), so it's paid, or held until the Town Pass, as every reward is.

use crate::chain::Bucket;
use crate::house::Payout;
use crate::{dice, AccountId, Event, Ref, Refusal, State, Usdc};

/// $2.00.
pub const PRIZE: Usdc = 2_000_000;
/// Two minutes to reach it.
pub const FOR_MS: u64 = 120_000;
/// The town's drop spots: the game knows where each one is.
pub const SPOTS: u64 = 6;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Loot {
    pub id: u64,
    pub spot: u64,
    pub prize: Usdc,
    pub ends_at: u64,
    pub claimed_by: Option<AccountId>,
    /// It ran out unclaimed.
    pub gone: bool,
}

impl Loot {
    pub fn out(&self, now_ms: u64) -> bool {
        self.claimed_by.is_none() && !self.gone && now_ms < self.ends_at
    }
}

impl State {
    /// After a paid meal: a crate falls, unless one is out already.
    pub(crate) fn drop_loot(&mut self, reference: &Ref, events: &mut Vec<Event>) {
        if self.loot.as_ref().is_some_and(|l| l.out(self.now_ms)) {
            return;
        }
        let loot = Loot {
            id: self.loot.as_ref().map_or(1, |l| l.id + 1),
            spot: dice::below(self.seed, "loot", reference, 0, SPOTS),
            prize: PRIZE,
            ends_at: self.now_ms + FOR_MS,
            claimed_by: None,
            gone: false,
        };
        events.push(Event::LootDropped {
            id: loot.id,
            spot: loot.spot,
            prize: loot.prize,
            ends_at: loot.ends_at,
        });
        self.loot = Some(loot);
    }

    /// First there: the crate is theirs, and so is its prize.
    pub(crate) fn claim_loot(
        &mut self,
        account: AccountId,
        id: u64,
        reference: Ref,
    ) -> Result<Vec<Event>, Refusal> {
        if self.life.player(&account).is_none() {
            return Err(Refusal::UnknownPlayer { account });
        }
        let now = self.now_ms;
        let Some(loot) = self.loot.as_mut().filter(|l| l.id == id && l.out(now)) else {
            return Err(Refusal::LootGone);
        };
        loot.claimed_by = Some(account.clone());
        let prize = loot.prize;
        let mut events = vec![Event::LootClaimed {
            id,
            account: account.clone(),
            prize,
        }];
        let payout = Payout::House {
            bucket: Bucket::Surprise,
        };
        self.reward(&account, payout, prize, "the loot crate", reference, &mut events);
        Ok(events)
    }

    /// A crate nobody reached in time is gone.
    pub(crate) fn expire_loot(&mut self, events: &mut Vec<Event>) {
        if let Some(loot) = self.loot.as_mut() {
            if loot.claimed_by.is_none() && !loot.gone && self.now_ms >= loot.ends_at {
                loot.gone = true;
                events.push(Event::LootGone { id: loot.id });
            }
        }
    }
}
