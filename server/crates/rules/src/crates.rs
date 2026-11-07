//! The quest crate (ux09): a quest done drops a crate at your feet, its tier drawn as it lands (most are wood, some brass, a few
//! gold). Opening it draws from the same table as the chest at your door, for that tier: its energy and tickets, perhaps a meal
//! voucher and perhaps a golden drop, paid from the surprise bucket like the chest's. Where it lands and what it holds come from
//! the seed, the player and how many crates they've had, so a replay drops and opens the same ones.

use crate::chain::Bucket;
use crate::house::{Category, Payout};
use crate::{dice, AccountId, ChestContents, Event, Refusal, State, Tier};

/// Out of 100: below `GOLD` a gold crate, below `BRASS` a brass one, else wood.
const GOLD: u64 = 5;
const BRASS: u64 = 30;

impl State {
    /// A quest is done: a crate lands, one at a time (an unopened one is replaced by the new one).
    pub(crate) fn drop_crate(&mut self, account: &str, quest: &str, events: &mut Vec<Event>) {
        let seed = self.seed;
        let Ok(player) = self.life.get_mut(account) else {
            return;
        };
        let n = u64::from(player.crates_dropped);
        player.crates_dropped += 1;
        let roll = dice::below(seed, "crate-tier", account, n, 100);
        let tier = if roll < GOLD {
            Tier::Gold
        } else if roll < BRASS {
            Tier::Brass
        } else {
            Tier::Wood
        };
        player.crate_waiting = Some(tier);
        events.push(Event::CrateDropped {
            account: account.to_string(),
            quest: quest.to_string(),
            tier,
        });
    }

    /// Hold E at the crate: what its tier's table draws.
    pub(crate) fn open_crate(&mut self, account: AccountId) -> Result<Vec<Event>, Refusal> {
        let now = self.now_ms;
        let c = self.config.chest;
        let player = self.life.get(&account)?;
        let Some(tier) = player.crate_waiting else {
            return Err(Refusal::NoCrate);
        };
        let odds = match tier {
            Tier::Wood => c.wood,
            Tier::Brass => c.brass,
            Tier::Gold => c.gold,
        };
        let n = u64::from(player.crates_opened);
        let rolled_drop = dice::chance(self.seed, "crate-drop", &account, n, odds.drop_bps);
        let mut voucher = dice::chance(self.seed, "crate-voucher", &account, n, odds.voucher_bps);
        let mut golden_drop = 0;
        if rolled_drop && self.house.category_left(Category::Chest, &self.config) >= c.golden_drop {
            golden_drop = self.house.take(Category::Chest, c.golden_drop, &self.config);
        }
        if voucher {
            let thali = self.voucher_value();
            voucher = thali > 0 && self.house.category_left(Category::Chest, &self.config) >= thali;
            if voucher {
                self.house.take(Category::Chest, thali, &self.config);
            }
        }
        let energy_config = self.config.energy;
        let player = self.life.get_mut(&account)?;
        player.crate_waiting = None;
        player.crates_opened += 1;
        if voucher {
            player.vouchers += 1;
        }
        player.add_energy(odds.energy, now, &energy_config);
        let contents = ChestContents {
            energy: odds.energy,
            tickets: odds.tickets,
            voucher,
            golden_drop,
        };
        let mut events = vec![Event::CrateOpened {
            account: account.clone(),
            tier,
            contents,
        }];
        self.add_tickets(&account, odds.tickets, "crate", &mut events);
        let payout = Payout::House {
            bucket: Bucket::Surprise,
        };
        let reference = format!("crate:{account}:{n}");
        self.reward(&account, payout, golden_drop, "golden drop", reference, &mut events);
        Ok(events)
    }
}
