//! Whole flows against the offline ledger, with no network: the world's intents go to the ledger, its observations
//! come back as logged inputs, exactly as the hub does it. And a save full of chain observations rebuilds the same
//! world, and the offline chain picks up where it was.

mod common;

use rules::chain::{Intent, Observed};
use rules::{Call, Command, Event, Refusal, Role};
use server::ledger::{keccak_of_hex, HumanId, Ledger, OfflineLedger};
use server::log::Log;
use server::world::{Input, World};
use std::path::PathBuf;

const RULES: &str = include_str!("../../../rules.toml");
const DAY: u64 = 24 * 3_600_000;
const USDC: u64 = 1_000_000;

struct Town {
    world: World,
    log: Log,
    ledger: OfflineLedger,
    /// Everything that happened, for looking through.
    seen: Vec<Event>,
}

impl Town {
    fn open(path: &std::path::Path) -> Town {
        let (log, world) = Log::open(path, RULES, 7).unwrap();
        let mut ledger = OfflineLedger::resume(RULES, &world.state).unwrap();
        for intent in world.state.open_intents() {
            ledger.submit(intent);
        }
        let mut town = Town {
            world,
            log,
            ledger,
            seen: Vec::new(),
        };
        town.pump();
        town
    }

    /// One input, logged, its intents carried to the ledger, as the hub does.
    fn take(&mut self, input: Input) -> Result<Vec<Event>, Refusal> {
        let events = self.world.step(input.clone())?;
        self.log.append(&input, &events).unwrap();
        for event in &events {
            if let Event::Intent { intent } = event {
                self.ledger.submit(intent.clone());
            }
        }
        self.seen.extend(events.clone());
        if let Some(week) = self.world.draw_due() {
            let seed = format!("0x{}", "11".repeat(32));
            let seed_hash = keccak_of_hex(&seed).unwrap();
            let commit = Command::CommitDraw {
                week,
                seed,
                seed_hash,
            };
            self.take(Input::Command {
                by: Role::Clock,
                command: commit,
            })
            .unwrap();
        }
        Ok(events)
    }

    fn chain(&mut self, observed: Vec<Observed>) -> Vec<Event> {
        let mut events = Vec::new();
        for o in observed {
            let input = Input::Chain {
                block: o.block,
                log_index: o.log_index,
                time: o.time,
                observed: o.observed,
            };
            if let Ok(more) = self.take(input) {
                events.extend(more);
            }
        }
        events
    }

    /// Lets the offline chain answer until it has nothing more to say.
    fn pump(&mut self) -> Vec<Event> {
        let mut events = Vec::new();
        loop {
            self.ledger.set_day(self.world.state.real_day());
            let observed = self.ledger.poll();
            if observed.is_empty() {
                return events;
            }
            events.extend(self.chain(observed));
        }
    }

    fn play(&mut self, command: Command) -> Result<Vec<Event>, Refusal> {
        let mut events = self.take(Input::Command {
            by: Role::Player,
            command,
        })?;
        events.extend(self.pump());
        Ok(events)
    }

    fn must(&mut self, command: Command) -> Vec<Event> {
        let what = format!("{command:?}");
        self.play(command)
            .unwrap_or_else(|r| panic!("{what}: {r:?}"))
    }

    fn connect(&mut self, name: &str) {
        self.take(Input::Connect {
            player: name.into(),
        })
        .unwrap();
        self.pump();
    }

    fn verify(&mut self, name: &str) -> Vec<Event> {
        let human_id = HumanId(format!("0x{name}-human"));
        let verify = Command::VerifyHuman {
            account: name.into(),
            human_id,
        };
        let mut events = self
            .take(Input::Command {
                by: Role::Verifier,
                command: verify,
            })
            .unwrap();
        events.extend(self.pump());
        events
    }

    fn fund(&mut self, name: &str, usdc: u64) {
        let observed = self.ledger.fund(name, usdc).unwrap();
        let stamped = self.ledger.stamp(observed);
        self.chain(stamped);
    }

    fn skip(&mut self, ms: u64) -> Vec<Event> {
        let mut events = self.take(Input::Advance { ms }).unwrap();
        events.extend(self.pump());
        events
    }

    fn usdc(&self, name: &str) -> u64 {
        self.world.state.life.player(name).unwrap().usdc.unwrap()
    }

    fn energy(&self, name: &str) -> u32 {
        let s = &self.world.state;
        s.life
            .player(name)
            .unwrap()
            .energy_now(s.now_ms, &s.config.energy)
    }

    /// Energy down to `to`: a rehearsal sponsor opens a campaign costing the difference, and it's taken and dropped.
    fn drain(&mut self, name: &str, to: u32) {
        let energy = self.energy(name) - to;
        let campaign = server::ledger::OfflineCampaign {
            template: "paint_sign".into(),
            sponsor: "drain".into(),
            budget: 10 * USDC,
            payout_per_claim: (u64::from(energy) * 3200).max(150_000),
            energy_cost: energy,
            max_claims: 5,
            per_human_cap: 5,
            days: 7,
            kind: 0,
        };
        let observed = self.ledger.open_campaign(&campaign).unwrap();
        let stamped = self.ledger.stamp(observed);
        self.chain(stamped);
        let id = self
            .world
            .state
            .campaigns
            .all()
            .map(|c| c.id)
            .max()
            .unwrap();
        let quest = format!("campaign:{id}");
        self.must(Command::TakeQuest {
            account: name.into(),
            quest: quest.clone(),
        });
        self.must(Command::AbandonQuest {
            account: name.into(),
            quest,
        });
        assert_eq!(self.energy(name), to);
    }

    /// Takes a quest that costs what's needed and drops it.
    fn hungry(&mut self, name: &str) {
        for quest in ["errand:chai_round", "errand:lost_ledger"] {
            if self
                .play(Command::TakeQuest {
                    account: name.into(),
                    quest: quest.into(),
                })
                .is_ok()
            {
                self.must(Command::AbandonQuest {
                    account: name.into(),
                    quest: quest.into(),
                });
            }
        }
    }
}

fn fresh_save(name: &str) -> PathBuf {
    let path = PathBuf::from(env!("CARGO_TARGET_TMPDIR")).join(format!("{name}.jsonl"));
    let _ = std::fs::remove_file(&path);
    path
}

fn has(events: &[Event], what: impl Fn(&Event) -> bool) -> bool {
    events.iter().any(what)
}

fn spice_run(town: &mut Town, name: &str) -> Vec<Event> {
    let quest = "campaign:1".to_string();
    let p = |command| command;
    town.must(p(Command::TakeQuest {
        account: name.into(),
        quest: quest.clone(),
    }));
    town.must(Command::QuestStep {
        account: name.into(),
        quest: quest.clone(),
        step: "cargo".into(),
    });
    town.must(Command::Swap {
        account: name.into(),
        quest: quest.clone(),
        reference: format!("{name}:swap"),
    });
    town.must(Command::Deliver {
        account: name.into(),
        quest,
        reference: format!("{name}:deliver"),
    })
}

#[test]
fn the_spice_run_runs_end_to_end_offline_with_an_advance_and_a_paid_claim() {
    let path = fresh_save("flow_spice");
    let mut town = Town::open(&path);
    town.connect("sam");
    assert!(
        town.world
            .state
            .life
            .player("sam")
            .unwrap()
            .wallet
            .is_some(),
        "a wallet at once"
    );
    assert_eq!(
        town.world.state.campaigns.board().count(),
        2,
        "the offline campaigns are on the board"
    );
    town.verify("sam");
    town.fund("sam", 200_000);
    let events = spice_run(&mut town, "sam");
    assert!(has(&events, |e| matches!(e, Event::QuestDone { .. })));
    assert!(has(
        &events,
        |e| matches!(e, Event::RewardPaid { amount, .. } if *amount == USDC)
    ));
    // 0.2 + 0.3 advanced − 0.5 swapped + (1.0 payout − 0.3 advance repaid).
    assert_eq!(town.usdc("sam"), 700_000);
    assert!(has(
        &town.seen,
        |e| matches!(e, Event::NameRegistered { name, .. } if name == "sam.tallyport.eth")
    ));
    assert!(has(
        &town.seen,
        |e| matches!(e, Event::RecordsSet { records, .. } if records.get("tallyport.stamps").is_some_and(|s| s.contains("spice-run")))
    ));
    let _ = std::fs::remove_file(&path);
}

#[test]
fn a_save_full_of_chain_observations_rebuilds_the_same_world_and_the_offline_chain_picks_up() {
    let path = fresh_save("flow_replay");
    let mut town = Town::open(&path);
    town.connect("sam");
    town.connect("priya");
    town.verify("sam");
    town.fund("sam", USDC);
    town.hungry("sam");
    town.must(Command::BuyMeal {
        account: "sam".into(),
        item: "thali".into(),
        voucher: false,
        reference: "sam:m1".into(),
    });
    spice_run(&mut town, "sam");
    town.must(Command::StartRush {
        account: "priya".into(),
    });
    town.must(Command::ServeOrder {
        account: "priya".into(),
        reference: "priya:o1".into(),
    });
    town.must(Command::EndRush {
        account: "priya".into(),
    });
    town.skip(DAY + 60_000);
    let world = town.world.clone();
    let seq = town.log.seq();
    drop(town);

    let mut back = Town::open(&path);
    assert_eq!(
        back.world, world,
        "every observation replays to the same world"
    );
    assert_eq!(
        back.log.seq(),
        seq,
        "the resumed offline chain had nothing new to say: no second campaigns, no repeats"
    );
    assert_eq!(back.world.state.campaigns.all().count(), 2);
    // And it goes on: priya's Rush pot was owed, and the Town Pass pays it.
    let owed = back.world.state.house.owed_to("priya");
    assert!(owed > 0);
    let events = back.verify("priya");
    assert!(has(
        &events,
        |e| matches!(e, Event::RewardPaid { account, amount, .. } if account == "priya" && *amount == owed)
    ));
    let _ = std::fs::remove_file(&path);
}

#[test]
fn a_chest_voucher_becomes_a_meal_the_house_pays_for() {
    let path = fresh_save("flow_voucher");
    let mut town = Town::open(&path);
    town.connect("sam");
    town.verify("sam");
    // Open chests until one has a voucher; every one is ready again by rehearsal.
    let mut voucher = false;
    for _ in 0..40 {
        town.take(Input::Command {
            by: Role::Clock,
            command: Command::ReadyChest {
                account: "sam".into(),
            },
        })
        .unwrap();
        let events = town.must(Command::OpenChest {
            account: "sam".into(),
            weekly: false,
        });
        voucher |= has(
            &events,
            |e| matches!(e, Event::ChestOpened { contents, .. } if contents.voucher),
        );
        if voucher {
            break;
        }
    }
    assert!(
        voucher,
        "a wood chest has a 10% voucher, and pity gives one when drops run out"
    );
    town.hungry("sam");
    let before = town.energy("sam");
    let events = town.must(Command::BuyMeal {
        account: "sam".into(),
        item: "thali".into(),
        voucher: true,
        reference: "sam:v".into(),
    });
    assert!(has(&events, |e| matches!(e, Event::VoucherUsed { .. })));
    assert!(has(&events, |e| matches!(e, Event::MealEaten { .. })));
    assert!(town.energy("sam") > before);
    let _ = std::fs::remove_file(&path);
}

#[test]
fn a_week_of_tickets_becomes_a_draw_committed_revealed_and_won_on_the_offline_chain() {
    let path = fresh_save("flow_draw");
    let mut town = Town::open(&path);
    town.connect("sam");
    town.verify("sam");
    town.must(Command::OpenChest {
        account: "sam".into(),
        weekly: false,
    });
    let events = town.skip(7 * DAY);
    assert!(
        has(&town.seen, |e| matches!(
            e,
            Event::DrawCommitted { week: 0, .. }
        )),
        "the week closed and its seed went in"
    );
    assert!(
        !has(&events, |e| matches!(
            e,
            Event::Intent {
                intent: Intent::RevealDraw { .. }
            }
        )),
        "the seed is revealed only after the wait"
    );
    let events = town.skip(11 * 60_000);
    assert!(has(
        &events,
        |e| matches!(e, Event::DrawWon { account, week: 0, .. } if account == "sam")
    ));
    assert_eq!(town.world.state.house.draw_reserved, 0);
    let _ = std::fs::remove_file(&path);
}

#[test]
fn a_stuck_person_gets_a_rescue_meal_from_the_safety_net() {
    let path = fresh_save("flow_rescue");
    let mut town = Town::open(&path);
    town.connect("sam");
    town.verify("sam");
    town.drain("sam", 50);
    town.must(Command::FreeMeal {
        account: "sam".into(),
    });
    town.drain("sam", 5);
    town.skip(60_000);
    let events = town.skip(3 * 60_000);
    assert!(
        has(&events, |e| matches!(
            e,
            Event::RescueMeal { direct: false, .. }
        )),
        "{events:?}"
    );
    assert!(town.energy("sam") >= 70);
    assert_eq!(town.world.state.house.stats.rescues_total, 1);
    let _ = std::fs::remove_file(&path);
}

#[test]
fn price_calls_and_errands_pay_through_the_offline_chain() {
    let path = fresh_save("flow_errand");
    let mut town = Town::open(&path);
    town.connect("sam");
    town.verify("sam");
    town.must(Command::PriceCall {
        account: "sam".into(),
        call: Call::Down,
    });
    let errand = "errand:price_board".to_string();
    town.must(Command::TakeQuest {
        account: "sam".into(),
        quest: errand.clone(),
    });
    town.must(Command::QuestStep {
        account: "sam".into(),
        quest: errand.clone(),
        step: "read".into(),
    });
    let events = town.must(Command::QuestStep {
        account: "sam".into(),
        quest: errand,
        step: "chalk".into(),
    });
    let rate = town.world.state.errand_rate();
    assert!(rate > 0);
    assert!(has(
        &events,
        |e| matches!(e, Event::RewardPaid { amount, .. } if *amount == rate)
    ));
    let events = town.skip(3_600_000);
    assert!(has(&events, |e| matches!(
        e,
        Event::PriceCallSettled { .. }
    )));
    let _ = std::fs::remove_file(&path);
}
