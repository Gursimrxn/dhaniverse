//! Quests: errands, sponsored quests from live campaigns (each template's steps and the chain's proof), Grandma's Ledger
//! and the day's mystery.

mod common;

use common::{intents, World, DAY, USDC};
use rules::chain::{Bucket, Intent, Observation};
use rules::house::Waiting;
use rules::{Command, Event, Refusal};

const SAM: &str = "sam";

fn campaign(
    w: &mut World,
    id: u64,
    template: &str,
    payout: u64,
    energy: u32,
    slots: u32,
    kind: u8,
) {
    w.observe(Observation::CampaignCreated {
        id,
        sponsor: "0xsponsor".into(),
        template: template.into(),
        meta_hash: "swarm-ref".into(),
        budget: 100 * USDC,
        payout_per_claim: payout,
        energy_cost: energy,
        max_claims: slots,
        per_human_cap: 1,
        start: 0,
        end: u64::MAX,
        kind,
        deliver_to: "0xsponsor".into(),
    })
    .unwrap();
}

fn take(w: &mut World, quest: &str) -> Result<Vec<Event>, Refusal> {
    w.run(Command::TakeQuest {
        account: SAM.into(),
        quest: quest.into(),
    })
}

fn step(w: &mut World, quest: &str, step: &str) -> Result<Vec<Event>, Refusal> {
    w.run(Command::QuestStep {
        account: SAM.into(),
        quest: quest.into(),
        step: step.into(),
    })
}

fn done(events: &[Event]) -> Option<&Event> {
    events.iter().find(|e| matches!(e, Event::QuestDone { .. }))
}

/// Answers the kiosk's quote request among these events, as Uniswap would.
fn quoted(w: &mut World, events: &[Event], amount_out: u128) -> Vec<Event> {
    let Some(Intent::QuoteSwap {
        player,
        campaign,
        usdc_in,
        reference,
    }) = intents(events)
        .into_iter()
        .find(|i| matches!(i, Intent::QuoteSwap { .. }))
    else {
        panic!("no quote asked for in {events:?}");
    };
    w.observe(Observation::SwapQuoted {
        player,
        campaign,
        usdc_in,
        amount_out,
        fee_bps: 3000,
        token: "0xmango".into(),
        symbol: "MANGO".into(),
        decimals: 18,
        reference,
    })
    .unwrap()
}

fn the_ref(events: &[Event]) -> String {
    intents(events)
        .iter()
        .find_map(|i| i.reference().map(str::to_string))
        .expect("an intent with a ref")
}

// ---------------------------------------------------------------- errands

#[test]
fn errands_cost_ten_energy_three_a_day_and_pay_the_days_errand_rate() {
    let mut w = World::new();
    w.pools(100 * USDC, 100 * USDC, 20 * USDC);
    w.verify(SAM);
    // 15% of the FIXED day budget (4% of 100 USDC) over 15 errands.
    assert_eq!(w.state.errand_rate(), 40_000);
    let errand = format!("errand:{}", w.state.book.errands[0].id);
    let events = take(&mut w, &errand).unwrap();
    assert!(events.contains(&Event::QuestTaken {
        account: SAM.into(),
        quest: errand.clone(),
        energy: 10
    }));
    assert_eq!(w.energy(SAM), 90);
    assert_eq!(
        take(&mut w, &errand),
        Err(Refusal::AlreadyOnQuest {
            quest: errand.clone()
        })
    );
    let steps: Vec<String> = w.state.book.errands[0]
        .steps
        .iter()
        .map(|s| s.id.clone())
        .collect();
    assert_eq!(
        step(&mut w, &errand, &steps[1]),
        Err(Refusal::WrongStep {
            quest: errand.clone(),
            step: steps[0].clone()
        }),
        "steps go in order"
    );
    step(&mut w, &errand, &steps[0]).unwrap();
    let events = step(&mut w, &errand, &steps[1]).unwrap();
    assert!(
        matches!(done(&events), Some(Event::QuestDone { reward, .. }) if reward.usdc == 40_000)
    );
    assert!(intents(&events).iter().any(|i| matches!(
        i,
        Intent::PayHouse {
            bucket: Bucket::Fixed,
            amount: 40_000,
            ..
        }
    )));
    for n in 1..3 {
        let errand = format!("errand:{}", w.state.book.errands[n].id);
        take(&mut w, &errand).unwrap();
    }
    let fourth = format!("errand:{}", w.state.book.errands[3].id);
    assert_eq!(
        take(&mut w, &fourth),
        Err(Refusal::NoErrandsLeft {
            most: 3,
            resets_at: DAY
        })
    );
    assert_eq!(
        take(&mut w, "errand:nope"),
        Err(Refusal::UnknownQuest {
            quest: "errand:nope".into()
        })
    );
}

#[test]
fn a_quest_needs_its_energy_and_abandoning_gives_back_the_slot_not_the_energy() {
    let mut w = World::new();
    campaign(&mut w, 1, "paint_sign", USDC, 20, 1, 0);
    w.set_energy(SAM, 10);
    assert_eq!(
        take(&mut w, "campaign:1"),
        Err(Refusal::NotEnoughEnergy { have: 10, need: 20 })
    );
    w.set_energy(SAM, 10);
    let mut w = World::new();
    campaign(&mut w, 1, "paint_sign", USDC, 20, 1, 0);
    take(&mut w, "campaign:1").unwrap();
    assert_eq!(w.state.campaigns.get(1).unwrap().slots_left(), 0);
    assert_eq!(
        w.run(Command::TakeQuest {
            account: "priya".into(),
            quest: "campaign:1".into()
        }),
        Err(Refusal::NoSlotsLeft { campaign: 1 }),
        "a slot is held from taking the quest"
    );
    w.run(Command::AbandonQuest {
        account: SAM.into(),
        quest: "campaign:1".into(),
    })
    .unwrap();
    assert_eq!(w.energy(SAM), 80);
    assert_eq!(w.state.campaigns.get(1).unwrap().slots_left(), 1);
}

// ---------------------------------------------------------------- the Spice Run

#[test]
fn the_spice_run_advances_short_cargo_swaps_on_chain_delivers_and_claims_the_payout() {
    let mut w = World::new();
    campaign(&mut w, 3, "spice_run", USDC, 30, 10, 0);
    take(&mut w, "campaign:3").unwrap();
    assert_eq!(
        step(&mut w, "campaign:3", "cargo"),
        Err(Refusal::NeedsTownPass),
        "an advance needs the Town Pass"
    );
    w.verify(SAM);
    w.fund(SAM, 200_000);
    let events = step(&mut w, "campaign:3", "cargo").unwrap();
    let advance = intents(&events);
    assert!(
        matches!(
            &advance[0],
            Intent::Advance {
                campaign: 3,
                amount: 300_000,
                ..
            }
        ),
        "the harbourmaster advances what the wallet is short: {advance:?}"
    );
    let reference = the_ref(&events);
    assert_eq!(
        w.run(Command::Swap {
            account: SAM.into(),
            quest: "campaign:3".into(),
            reference: "s1".into()
        }),
        Err(Refusal::StepWaiting {
            quest: "campaign:3".into(),
            step: "cargo".into()
        })
    );
    let events = w
        .observe(Observation::Advanced {
            campaign: 3,
            player: SAM.into(),
            human_id: World::human(SAM),
            amount: 300_000,
            reference,
            tx: "0xa".into(),
        })
        .unwrap();
    quoted(&mut w, &events, 9_066_000_000_000_000_000);
    w.fund(SAM, 500_000);
    let events = w
        .run(Command::Swap {
            account: SAM.into(),
            quest: "campaign:3".into(),
            reference: "s1".into(),
        })
        .unwrap();
    assert!(matches!(
        &intents(&events)[0],
        Intent::SwapForQuest {
            usdc_in: 500_000,
            campaign: 3,
            ..
        }
    ));
    let events = w
        .observe(Observation::QuestSwap {
            player: SAM.into(),
            token_in: "USDC".into(),
            token_out: "MANGO".into(),
            amount_in: 500_000,
            amount_out: 42,
            tx: "0xs".into(),
        })
        .unwrap();
    assert!(events
        .iter()
        .any(|e| matches!(e, Event::QuestStepDone { step, .. } if step == "swap")));
    assert!(
        events.iter().any(|e| matches!(
            e,
            Event::QuestSwapped { quest, received: 42, .. } if quest == "campaign:3"
        )),
        "the player hears what actually arrived"
    );
    let events = w
        .run(Command::Deliver {
            account: SAM.into(),
            quest: "campaign:3".into(),
            reference: "d1".into(),
        })
        .unwrap();
    let reference = the_ref(&events);
    let events = w
        .observe(Observation::Delivered {
            campaign: 3,
            player: SAM.into(),
            token: "MANGO".into(),
            amount: 42,
            reference,
            tx: "0xd".into(),
        })
        .unwrap();
    assert!(
        matches!(done(&events), Some(Event::QuestDone { reward, .. }) if reward.usdc == USDC && reward.title.as_deref() == Some("Spice Runner"))
    );
    let claim = intents(&events)
        .into_iter()
        .find(|i| matches!(i, Intent::ClaimCampaign { .. }))
        .expect("a claim");
    let Intent::ClaimCampaign {
        amount, reference, ..
    } = claim
    else {
        unreachable!()
    };
    assert_eq!(amount, USDC);
    let events = w
        .observe(Observation::Claimed {
            campaign: 3,
            player: SAM.into(),
            human_id: World::human(SAM),
            amount: 700_000,
            advance_repaid: 300_000,
            reference,
            tx: "0xc".into(),
        })
        .unwrap();
    assert!(events
        .iter()
        .any(|e| matches!(e, Event::RewardPaid { amount, .. } if *amount == USDC)));
    let c = w.state.campaigns.get(3).unwrap();
    assert_eq!((c.claims, c.held, c.humans.len()), (1, 0, 1));
    assert_eq!(w.state.title(SAM), "Spice Runner");
    assert_eq!(
        take(&mut w, "campaign:3"),
        Err(Refusal::PerHumanCap {
            campaign: 3,
            cap: 1
        })
    );
}

#[test]
fn a_swap_the_chain_refused_can_be_tried_again() {
    let mut w = World::new();
    campaign(&mut w, 3, "spice_run", USDC, 30, 10, 0);
    w.fund(SAM, USDC);
    take(&mut w, "campaign:3").unwrap();
    let events = step(&mut w, "campaign:3", "cargo").unwrap();
    quoted(&mut w, &events, 1_000_000);
    assert_eq!(
        w.run(Command::Swap {
            account: SAM.into(),
            quest: "campaign:3".into(),
            reference: "s1".into()
        })
        .map(|e| intents(&e).len()),
        Ok(1)
    );
    let events = w
        .observe(Observation::IntentFailed {
            reference: "s1".into(),
            reason: "V4TooLittleReceived".into(),
        })
        .unwrap();
    assert!(matches!(&events[0], Event::QuestStepFailed { step, .. } if step == "swap"));
    assert_eq!(
        w.run(Command::Swap {
            account: SAM.into(),
            quest: "campaign:3".into(),
            reference: "s1".into()
        }),
        Err(Refusal::RefUsed {
            reference: "s1".into()
        }),
        "a new try needs a new ref"
    );
    w.run(Command::Swap {
        account: SAM.into(),
        quest: "campaign:3".into(),
        reference: "s2".into(),
    })
    .unwrap();
}

#[test]
fn reaching_the_swap_asks_the_kiosk_for_a_quote_and_the_swap_takes_at_least_it_less_slippage() {
    let mut w = World::new();
    campaign(&mut w, 3, "spice_run", USDC, 30, 10, 0);
    w.fund(SAM, USDC);
    take(&mut w, "campaign:3").unwrap();
    let swap = |w: &mut World, reference: &str| {
        w.run(Command::Swap {
            account: SAM.into(),
            quest: "campaign:3".into(),
            reference: reference.into(),
        })
    };
    let events = step(&mut w, "campaign:3", "cargo").unwrap();
    let asked = intents(&events);
    assert!(
        matches!(
            &asked[..],
            [Intent::QuoteSwap {
                usdc_in: 500_000,
                campaign: 3,
                ..
            }]
        ),
        "the swap step asks for its first quote by itself: {asked:?}"
    );
    assert_eq!(
        swap(&mut w, "s1"),
        Err(Refusal::QuoteStale {
            quest: "campaign:3".into()
        }),
        "no quote yet, no swap"
    );
    let events = quoted(&mut w, &events, 9_066_000_000_000_000_000);
    assert!(events.iter().any(|e| matches!(
        e,
        Event::SwapQuoted { min_out, fee_bps: 3000, slippage_bps: 100, .. } if *min_out == 8_975_340_000_000_000_000
    )), "{events:?}");
    let events = swap(&mut w, "s1").unwrap();
    assert!(
        matches!(&intents(&events)[0], Intent::SwapForQuest { min_out, .. } if *min_out == 8_975_340_000_000_000_000),
        "1% under the quote"
    );
}

#[test]
fn a_quote_goes_stale_after_a_minute_and_can_be_asked_for_every_fifteen_seconds() {
    let mut w = World::new();
    campaign(&mut w, 3, "spice_run", USDC, 30, 10, 0);
    w.fund(SAM, USDC);
    take(&mut w, "campaign:3").unwrap();
    let ask = |w: &mut World| {
        w.run(Command::QuoteSwap {
            account: SAM.into(),
            quest: "campaign:3".into(),
        })
    };
    assert_eq!(
        ask(&mut w),
        Err(Refusal::WrongStep {
            quest: "campaign:3".into(),
            step: "cargo".into()
        }),
        "only at the swap"
    );
    let events = step(&mut w, "campaign:3", "cargo").unwrap();
    quoted(&mut w, &events, 5_000);
    assert_eq!(ask(&mut w), Err(Refusal::QuoteTooSoon { ready_at: 15_000 }));
    w.at(61_000);
    assert_eq!(
        w.run(Command::Swap {
            account: SAM.into(),
            quest: "campaign:3".into(),
            reference: "s1".into()
        }),
        Err(Refusal::QuoteStale {
            quest: "campaign:3".into()
        }),
        "a minute-old quote is too old to swap on"
    );
    let events = ask(&mut w).unwrap();
    let events = quoted(&mut w, &events, 5_000);
    assert!(events.iter().any(|e| matches!(e, Event::SwapQuoted { .. })));
    w.run(Command::Swap {
        account: SAM.into(),
        quest: "campaign:3".into(),
        reference: "s1".into(),
    })
    .unwrap();

    let failed = Observation::IntentFailed {
        reference: "never".into(),
        reason: "x".into(),
    };
    assert!(w.observe(failed).is_err());
}

#[test]
fn a_quote_that_failed_can_be_asked_for_again_at_once() {
    let mut w = World::new();
    campaign(&mut w, 3, "spice_run", USDC, 30, 10, 0);
    w.fund(SAM, USDC);
    take(&mut w, "campaign:3").unwrap();
    let events = step(&mut w, "campaign:3", "cargo").unwrap();
    let events = w
        .observe(Observation::IntentFailed {
            reference: the_ref(&events),
            reason: "no pool".into(),
        })
        .unwrap();
    assert!(matches!(&events[0], Event::QuoteFailed { reason, .. } if reason == "no pool"));
    w.run(Command::QuoteSwap {
        account: SAM.into(),
        quest: "campaign:3".into(),
    })
    .unwrap();
}

#[test]
fn the_least_out_rounds_down_and_never_overflows() {
    use rules::quests::min_out;
    assert_eq!(min_out(10_000, 100), 9_900);
    assert_eq!(min_out(9_999, 100), 9_899);
    assert_eq!(min_out(u128::MAX, 0), u128::MAX);
    assert_eq!(min_out(u128::MAX, 10_000), 0);
}

// ---------------------------------------------------------------- Paint your sign, the Town Pass, Hold the Line

#[test]
fn painting_the_sign_needs_a_name_and_finishes_when_the_record_is_seen_on_chain() {
    let mut w = World::new();
    campaign(&mut w, 4, "paint_sign", 250_000, 20, 10, 0);
    take(&mut w, "campaign:4").unwrap();
    step(&mut w, "campaign:4", "painter").unwrap();
    let paint = |text: &str| Command::PaintSign {
        account: SAM.into(),
        text: text.into(),
    };
    assert_eq!(w.run(paint("Sam's chai")), Err(Refusal::NoName));
    w.observe(Observation::NameRegistered {
        player: SAM.into(),
        label: SAM.into(),
        name: "sam.tallyport.eth".into(),
        tx: "0x".into(),
    })
    .unwrap();
    assert_eq!(w.run(paint("")), Err(Refusal::BadSign { most: 80 }));
    assert_eq!(
        w.run(paint(&"x".repeat(81))),
        Err(Refusal::BadSign { most: 80 })
    );
    assert_eq!(
        w.run(paint("two\nlines")),
        Err(Refusal::BadSign { most: 80 })
    );
    let events = w.run(paint("Sam's chai")).unwrap();
    assert!(
        matches!(&intents(&events)[0], Intent::SetRecords { records, .. } if records["description"] == "Sam's chai")
    );
    let events = w
        .observe(Observation::RecordsSet {
            player: SAM.into(),
            records: [("description".to_string(), "Sam's chai".to_string())].into(),
            tx: "0x".into(),
        })
        .unwrap();
    assert!(
        matches!(done(&events), Some(Event::QuestDone { reward, .. }) if reward.usdc == 250_000)
    );
    assert!(
        events.iter().any(|e| matches!(
            e,
            Event::RewardPending {
                waiting: Waiting::TownPass,
                ..
            }
        )),
        "the payout waits for the Town Pass"
    );
}

#[test]
fn the_town_pass_quest_finishes_on_verifying_or_at_once_for_someone_who_already_has_it() {
    let mut w = World::new();
    campaign(&mut w, 5, "town_pass", 200_000, 0, 10, 0);
    take(&mut w, "campaign:5").unwrap();
    step(&mut w, "campaign:5", "clerk").unwrap();
    let events = w.verify(SAM);
    assert!(done(&events).is_some());
    assert!(intents(&events).iter().any(|i| matches!(
        i,
        Intent::ClaimCampaign {
            amount: 200_000,
            ..
        }
    )));

    w.verify("priya");
    w.run(Command::TakeQuest {
        account: "priya".into(),
        quest: "campaign:5".into(),
    })
    .unwrap();
    let events = w
        .run(Command::QuestStep {
            account: "priya".into(),
            quest: "campaign:5".into(),
            step: "clerk".into(),
        })
        .unwrap();
    assert!(
        events
            .iter()
            .any(|e| matches!(e, Event::QuestStepDone { step, .. } if step == "verify")),
        "the pass they already hold does the step as soon as it's reached"
    );
    assert!(done(&events).is_some());
}

#[test]
fn hold_the_line_checks_the_balance_at_random_and_fails_if_it_drops() {
    let mut w = World::new();
    campaign(&mut w, 6, "hold_line", USDC, 20, 10, 0);
    let events = take(&mut w, "campaign:6").unwrap();
    let first = the_ref(&events);
    assert!(
        matches!(
            &intents(&events)[0],
            Intent::CheckHolding { campaign: 6, .. }
        ),
        "the first check is at once"
    );
    let line = 1_000_000_000_000_000_000u128;
    w.observe(Observation::Holding {
        player: SAM.into(),
        campaign: 6,
        amount: line,
        reference: first,
    })
    .unwrap();
    step(&mut w, "campaign:6", "trader").unwrap();
    // Over three days the other checks go out, one at a time.
    let mut checks = 1;
    for _ in 0..(3 * 24) {
        let events = w.later(DAY / 24);
        for intent in intents(&events) {
            if let Intent::CheckHolding { reference, .. } = intent {
                checks += 1;
                w.observe(Observation::Holding {
                    player: SAM.into(),
                    campaign: 6,
                    amount: line,
                    reference,
                })
                .unwrap();
            }
        }
        if w.player(SAM).quests.is_empty() {
            break;
        }
    }
    assert_eq!(checks, 3);
    assert!(w.player(SAM).quests.is_empty(), "held for three days: done");
    assert_eq!(w.player(SAM).quests_done, 1);

    let mut w = World::new();
    campaign(&mut w, 6, "hold_line", USDC, 20, 10, 0);
    let first = the_ref(&take(&mut w, "campaign:6").unwrap());
    let events = w
        .observe(Observation::Holding {
            player: SAM.into(),
            campaign: 6,
            amount: line - 1,
            reference: first,
        })
        .unwrap();
    assert!(matches!(&events[0], Event::QuestFailed { .. }));
    assert_eq!(
        w.state.campaigns.get(6).unwrap().slots_left(),
        10,
        "the slot is free again"
    );
}

#[test]
fn closed_boosted_and_unknown_campaigns_are_not_on_the_board() {
    let mut w = World::new();
    campaign(&mut w, 7, "spice_run", USDC, 30, 10, 1);
    assert_eq!(
        take(&mut w, "campaign:7"),
        Err(Refusal::UnknownQuest {
            quest: "campaign:7".into()
        }),
        "a boosted campaign sponsors the mystery, not a card"
    );
    campaign(&mut w, 8, "spice_run", USDC, 30, 10, 0);
    w.observe(Observation::CampaignClosed {
        campaign: 8,
        tx: "0x".into(),
    })
    .unwrap();
    assert_eq!(
        take(&mut w, "campaign:8"),
        Err(Refusal::CampaignClosed { campaign: 8 })
    );
    assert_eq!(w.state.campaigns.board().count(), 0);
    assert_eq!(
        take(&mut w, "campaign:99"),
        Err(Refusal::UnknownQuest {
            quest: "campaign:99".into()
        })
    );
}

// ---------------------------------------------------------------- Grandma's Ledger and mysteries

#[test]
fn grandmas_pages_are_found_by_real_things_in_any_order_and_the_strongbox_is_last() {
    let mut w = World::new();
    w.pools(100 * USDC, 100 * USDC, 20 * USDC);
    take(&mut w, "grandma").unwrap();
    assert_eq!(w.energy(SAM), 50);
    assert_eq!(step(&mut w, "grandma", "paper"), Err(Refusal::NotAShockDay));
    assert_eq!(
        step(&mut w, "grandma", "strongbox"),
        Err(Refusal::WrongStep {
            quest: "grandma".into(),
            step: "paper".into()
        })
    );
    step(&mut w, "grandma", "clerk").unwrap();
    assert_eq!(
        step(&mut w, "grandma", "meals"),
        Err(Refusal::WrongStep {
            quest: "grandma".into(),
            step: "paper".into()
        }),
        "meals are counted, not reported"
    );
    w.run(Command::AnnounceCityEvent {
        kind: "drought".into(),
        days: 2,
    })
    .unwrap();
    step(&mut w, "grandma", "paper").unwrap();
    w.fund(SAM, USDC);
    for n in 0..3 {
        let reference = format!("m{n}");
        w.run(Command::BuyMeal {
            account: SAM.into(),
            item: "chai".into(),
            voucher: false,
            reference: reference.clone(),
        })
        .unwrap();
        let events = w
            .observe(Observation::MealEaten {
                player: SAM.into(),
                item: "chai".into(),
                usdc: 1000,
                food: 1_000_000,
                from_ration: 0,
                reference,
                tx: "0x".into(),
            })
            .unwrap();
        let page = events
            .iter()
            .any(|e| matches!(e, Event::QuestStepDone { step, .. } if step == "meals"));
        assert_eq!(page, n == 2, "the third paid meal finds the page");
    }
    let events = step(&mut w, "grandma", "strongbox").unwrap();
    // 1 USDC, within the mystery share: 15% of 4 USDC is 0.6 USDC, so 0.6.
    assert!(
        matches!(done(&events), Some(Event::QuestDone { reward, .. })
        if reward.usdc == 600_000 && reward.title.as_deref() == Some("Grandma's Heir"))
    );
    assert_eq!(
        take(&mut w, "grandma"),
        Err(Refusal::QuestDoneBefore {
            quest: "grandma".into()
        }),
        "once a season"
    );
}

#[test]
fn only_todays_mystery_can_be_taken_once_a_day_and_a_boosted_one_pays_from_its_campaign() {
    let mut w = World::new();
    let (today, _) = w.state.todays_mystery().unwrap();
    let today = format!("mystery:{}", today.id);
    let other = w
        .state
        .book
        .mysteries
        .iter()
        .map(|m| format!("mystery:{}", m.id))
        .find(|m| *m != today)
        .unwrap();
    assert_eq!(
        take(&mut w, &other),
        Err(Refusal::UnknownQuest {
            quest: other.clone()
        })
    );
    take(&mut w, &today).unwrap();
    assert_eq!(w.energy(SAM), 50);
    w.run(Command::AbandonQuest {
        account: SAM.into(),
        quest: today.clone(),
    })
    .unwrap();
    assert!(matches!(
        take(&mut w, &today),
        Err(Refusal::NoMysteryLeft { most: 1, .. })
    ));

    let mut w = World::new();
    campaign(&mut w, 9, "spice_run", 2 * USDC, 50, 10, 1);
    assert_eq!(w.state.mystery_payout(), 2 * USDC);
    let (text, boosted) = w.state.todays_mystery().unwrap();
    assert_eq!(boosted, Some(9));
    let quest = format!("mystery:{}", text.id);
    let steps: Vec<String> = text.steps.iter().map(|s| s.id.clone()).collect();
    w.verify(SAM);
    take(&mut w, &quest).unwrap();
    let mut events = Vec::new();
    for id in steps {
        events = step(&mut w, &quest, &id).unwrap();
    }
    assert!(intents(&events).iter().any(
        |i| matches!(i, Intent::ClaimCampaign { campaign: 9, amount, .. } if *amount == 2 * USDC)
    ));
}
