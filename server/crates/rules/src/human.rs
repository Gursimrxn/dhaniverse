//! Who someone is: their wallet, the Town Pass that proves they're one person, their ENS name and what's written on
//! it, and who sent them. Every USDC payout waits for the Town Pass; getting it pays what was owed.

use crate::book::StepKind;
use crate::chain::{HumanId, Intent};
use crate::{is_person, AccountId, Event, Refusal, State};
use std::collections::BTreeMap;

impl State {
    /// A new player. They get a wallet from the chain: nobody deposits anything to start.
    pub(crate) fn arrive(&mut self, account: AccountId) -> Result<Vec<Event>, Refusal> {
        let energy = self.config.energy.start.min(self.config.energy.max);
        let mut events = self.life.arrive(account.clone(), energy, self.now_ms)?;
        if is_person(&account) {
            self.ask(Intent::EnsureWallet { player: account }, &mut events);
        }
        Ok(events)
    }

    /// World ID says this player is a person. One person, one player: a World ID already holding someone else is
    /// refused. Their ENS name is registered, and everything owed to them goes out.
    pub(crate) fn verify_human(
        &mut self,
        account: AccountId,
        human_id: HumanId,
    ) -> Result<Vec<Event>, Refusal> {
        let player = self.life.get(&account)?;
        if player.human.is_some() {
            return Err(Refusal::AlreadyHuman);
        }
        if self
            .chain
            .humans
            .get(&human_id)
            .is_some_and(|holder| *holder != account)
        {
            return Err(Refusal::HumanTaken);
        }
        self.chain.humans.insert(human_id.clone(), account.clone());
        let player = self.life.get_mut(&account)?;
        player.human = Some(human_id);
        let named = player.ens.is_some();
        let mut events = vec![Event::HumanVerified {
            account: account.clone(),
        }];
        if !named {
            let intent = Intent::RegisterName {
                player: account.clone(),
                label: account.clone(),
            };
            self.ask(intent, &mut events);
        }
        self.finish_steps_of(&account, StepKind::Verify, &mut events);
        self.retry_owed(Some(&account), &mut events);
        self.check_referral(&account, &mut events);
        Ok(events)
    }

    /// The player's own sign, on their ENS name's `description`, written from their own wallet.
    pub(crate) fn paint_sign(
        &mut self,
        account: AccountId,
        text: String,
    ) -> Result<Vec<Event>, Refusal> {
        let most = self.config.templates.paint_sign.most_chars;
        let text = text.trim().to_string();
        let count = text.chars().count();
        if count == 0 || count > most || text.chars().any(char::is_control) {
            return Err(Refusal::BadSign { most });
        }
        let player = self.life.get(&account)?;
        if player.ens.is_none() {
            return Err(Refusal::NoName);
        }
        let mut events = vec![Event::SignPainting {
            account: account.clone(),
            text: text.clone(),
        }];
        let records = BTreeMap::from([("description".to_string(), text)]);
        self.ask(
            Intent::SetRecords {
                player: account,
                records,
            },
            &mut events,
        );
        Ok(events)
    }

    /// Title, stamps and the Town Pass mark, on a player's name. Only once they have one.
    pub(crate) fn write_profile_records(&mut self, account: &str, events: &mut Vec<Event>) {
        let title = self.title(account);
        let Some(player) = self.life.player(account) else {
            return;
        };
        if player.ens.is_none() {
            return;
        }
        let mut records = BTreeMap::new();
        records.insert("tallyport.title".to_string(), title);
        let stamps: Vec<&str> = player.stamps.iter().map(String::as_str).collect();
        records.insert("tallyport.stamps".to_string(), stamps.join(","));
        if player.human.is_some() {
            records.insert("tallyport.human".to_string(), "verified".to_string());
        }
        let intent = Intent::SetRecords {
            player: account.to_string(),
            records,
        };
        self.ask(intent, events);
    }

    /// Names who sent them. Only before their first quest is done, and only once.
    pub(crate) fn refer(
        &mut self,
        account: AccountId,
        by: AccountId,
    ) -> Result<Vec<Event>, Refusal> {
        if account == by {
            return Err(Refusal::ReferringYourself);
        }
        if !is_person(&by) {
            return Err(Refusal::UnknownPlayer { account: by });
        }
        self.life.check_arrived(&by)?;
        let player = self.life.get_mut(&account)?;
        if player.referrer.is_some() {
            return Err(Refusal::AlreadyReferred);
        }
        if player.quests_done > 0 {
            return Err(Refusal::TooLateToRefer);
        }
        player.referrer = Some(by.clone());
        Ok(vec![Event::Referred { account, by }])
    }

    /// Both get their tickets once the friend has the Town Pass and a finished quest.
    pub(crate) fn check_referral(&mut self, account: &str, events: &mut Vec<Event>) {
        let Some(player) = self.life.player(account) else {
            return;
        };
        let ready = player.human.is_some() && player.quests_done > 0 && !player.referral_paid;
        let Some(by) = player.referrer.clone().filter(|_| ready) else {
            return;
        };
        if let Ok(player) = self.life.get_mut(account) {
            player.referral_paid = true;
        }
        let tickets = self.config.referral.tickets;
        events.push(Event::ReferralRewarded {
            account: by.clone(),
            friend: account.to_string(),
            tickets,
        });
        self.add_tickets(account, tickets, "referral", events);
        self.add_tickets(&by, tickets, "referral", events);
    }

    /// Whether this player may start the Town Pass, and the wallet World ID will be told about.
    pub fn town_pass_check(&self, account: &str) -> Result<String, Refusal> {
        let player = self.life.get(account)?;
        if player.human.is_some() {
            return Err(Refusal::AlreadyHuman);
        }
        player.wallet.clone().ok_or(Refusal::NoWallet)
    }
}
