//! The Tally's wording: facts in, a front page out. It reads nothing else, so a model can replace this one function
//! later and still can't print what didn't happen.

use super::facts::Facts;
use rules::First;

/// How big a move must be to make the headline.
const FOOD_HEADLINE_BPS: i64 = 300;
/// A front page is short.
const MOST_STORIES: usize = 5;
const MOST_NAMES: usize = 3;
const MOST_MENU_CHANGES: usize = 2;
const USDC_UNIT: u64 = 1_000_000;

pub struct FrontPage {
    pub headline: String,
    pub stories: Vec<String>,
}

pub fn write(facts: &Facts) -> FrontPage {
    let mut stories = Vec::new();
    stories.extend(
        facts
            .city_events
            .iter()
            .map(|e| city_event_story(&e.kind, e.days)),
    );
    stories.extend(food_story(facts));
    stories.extend(firsts_story(facts));
    stories.truncate(MOST_STORIES);
    FrontPage {
        headline: headline(facts),
        stories,
    }
}

/// The biggest thing that happened. What the harvest does reaches everyone's plate, so it comes first.
fn headline(facts: &Facts) -> String {
    if let Some(event) = facts.city_events.first() {
        return match event.kind.as_str() {
            "festival" => "A festival brings a crowd to town".to_string(),
            "harvest" => "A good harvest reaches the market".to_string(),
            "drought" => "A poor harvest hits the market".to_string(),
            other => format!("Tallyport wakes to a {other}"),
        };
    }
    if let Some(change) = food_change_bps(facts) {
        if change.abs() >= FOOD_HEADLINE_BPS {
            let verb = if change > 0 { "jump" } else { "fall" };
            return format!("Food prices {verb} {}", move_size(change));
        }
    }
    if let Some((name, first)) = facts.firsts.first() {
        return format!("{name} {}", first_phrase(*first));
    }
    "A quiet day in Tallyport".to_string()
}

fn city_event_story(kind: &str, days: u32) -> String {
    let how_long = match days {
        1 => "today".to_string(),
        n => format!("for {n} days"),
    };
    match kind {
        "festival" => format!(
            "A festival runs {how_long}. More people will be out eating, so food may get dearer."
        ),
        "harvest" => format!(
            "A good harvest is coming in {how_long}. With more food to sell, prices may ease."
        ),
        "drought" => {
            format!("The harvest is poor {how_long}. With less food to sell, prices may climb.")
        }
        other => format!("A {other} starts {how_long}."),
    }
}

fn food_story(facts: &Facts) -> Option<String> {
    let food = facts.food.as_ref()?;
    if food.day_price == 0 {
        return Some("Nobody traded food yesterday, so prices stayed where they were.".to_string());
    }
    let mut story = format!(
        "A unit of food cost {} USDC on average yesterday",
        usdc(food.day_price)
    );
    match food_change_bps(facts) {
        Some(change) if change > 0 => story.push_str(&format!(", up {}.", move_size(change))),
        Some(change) if change < 0 => story.push_str(&format!(", down {}.", move_size(change))),
        Some(_) => story.push_str(", the same as the day before."),
        None => story.push('.'),
    }
    for change in facts.menu_changes.iter().take(MOST_MENU_CHANGES) {
        story.push_str(&format!(
            " A {} now costs {} USDC, {} from {}.",
            dish(&change.name),
            usdc(change.to),
            if change.to > change.from {
                "up"
            } else {
                "down"
            },
            usdc(change.from)
        ));
    }
    if facts.short_batches > 0 {
        story.push_str(" The market hit its daily limit, and some stalls ran short.");
    }
    if facts.unsold_slices > 0 {
        story.push_str(" Kofi hit the daily limit, and took some food home unsold.");
    }
    Some(story)
}

/// A menu item as you'd say it out loud.
fn dish(name: &str) -> &str {
    match name {
        "vada_pav" => "vada pav",
        other => other,
    }
}

fn firsts_story(facts: &Facts) -> Option<String> {
    let (first_name, first) = facts.firsts.first()?;
    let mut parts = vec![format!("{first_name} {}", first_phrase(*first))];
    for (name, first) in facts.firsts.iter().skip(1).take(MOST_NAMES - 1) {
        parts.push(format!("{name} {}", first_phrase(*first)));
    }
    let others = facts.firsts.len().saturating_sub(MOST_NAMES);
    let mut story = parts.join(", and ");
    story.push('.');
    if others > 0 {
        let (firsts, were) = if others == 1 {
            ("first", "was")
        } else {
            ("firsts", "were")
        };
        story.push_str(&format!(
            " {others} more {firsts} {were} earned around town."
        ));
    }
    Some(story)
}

fn first_phrase(first: First) -> &'static str {
    match first {
        First::FirstMeal => "bought a first meal",
        First::FirstQuest => "finished a first quest",
        First::TownPass => "got the Town Pass",
    }
}

fn food_change_bps(facts: &Facts) -> Option<i64> {
    let food = facts.food.as_ref()?;
    let previous = food.previous_day_price.filter(|p| *p > 0)?;
    (food.day_price != 0)
        .then(|| (food.day_price as i64 - previous as i64) * 10_000 / previous as i64)
}

/// 212 bps → "2.1%", always positive: the words say which way.
fn move_size(bps: i64) -> String {
    let bps = bps.abs();
    format!("{}.{}%", bps / 100, (bps % 100) / 10)
}

/// USDC base units as a decimal with no trailing zeros: 1,020 → "0.00102", 1,500,000 → "1.5".
pub(crate) fn usdc(units: u64) -> String {
    let (whole, fraction) = (units / USDC_UNIT, units % USDC_UNIT);
    if fraction == 0 {
        return whole.to_string();
    }
    let digits = format!("{fraction:06}");
    format!("{whole}.{}", digits.trim_end_matches('0'))
}
