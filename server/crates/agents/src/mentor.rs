//! The mentor: after something real happens to a player, it names the thing, once. `read` finds what happened in that
//! player's own events, and `words` says it, so a model can replace the wording later and still can't speak early.

use rules::{is_person, AccountId, Command, Event, Usdc};
use std::collections::{BTreeMap, BTreeSet};

/// A thing a player can meet.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord)]
pub enum Lesson {
    Inflation,
}

pub const ALL_LESSONS: [Lesson; 1] = [Lesson::Inflation];

impl Lesson {
    /// The `about` field in PROTOCOL.md.
    pub fn about(self) -> &'static str {
        match self {
            Lesson::Inflation => "inflation",
        }
    }

    /// The words a player's question might use for this, and the only place the term itself may appear in `words`.
    pub fn terms(self) -> &'static [&'static str] {
        match self {
            Lesson::Inflation => &["inflation", "price"],
        }
    }
}

/// The plain words for a lesson. They only speak of what has just happened, and name it last.
pub fn words(lesson: Lesson) -> &'static str {
    match lesson {
        Lesson::Inflation => "Same meal, more money. Your money buys a little less than it did. When prices rise across a town, it's called inflation.",
    }
}

const NOT_YET: &str = "That hasn't come up for you yet. Ask me again when it does.";
const NOTHING_YET: &str = "Nothing much has happened to you yet. Go and see the town, and come back when something surprises you.";

/// What the mentor says to a question, from what this player has met. Only someone who met a thing hears about it.
pub fn answer(question: &str, met: &BTreeSet<Lesson>) -> (&'static str, &'static str) {
    let question = question.to_lowercase();
    let asked = |lesson: &Lesson| lesson.terms().iter().any(|term| question.contains(term));
    if let Some(lesson) = met.iter().find(|l| asked(l)) {
        return (lesson.about(), words(*lesson));
    }
    if ALL_LESSONS.iter().any(asked) {
        return ("reply", NOT_YET);
    }
    match met.iter().next_back() {
        Some(lesson) => (lesson.about(), words(*lesson)),
        None => ("reply", NOTHING_YET),
    }
}

/// The words, from a model if one is given and it answers, and otherwise the plain ones, so a failed call changes nothing
/// for the player.
// ponytail: no model is wired in. When one is, its text has to reach the world as an input, like any other, or a replay
// would get different words.
pub fn words_from<E>(lesson: Lesson, model: impl FnOnce(Lesson) -> Result<String, E>) -> String {
    model(lesson).unwrap_or_else(|_| words(lesson).to_string())
}

/// What a player has met, from their own events, and what the mentor still has to say to them.
#[derive(Clone, Debug, Default, PartialEq, Eq)]
pub struct Mentor {
    met: BTreeMap<AccountId, BTreeSet<Lesson>>,
    /// What each player last paid for each meal, so they meet a price rise themselves.
    last_paid: BTreeMap<(AccountId, String), Usdc>,
}

impl Mentor {
    /// Reads these events, and returns what to say. Each thing is said once, to the person it happened to.
    pub fn read(&mut self, events: &[Event]) -> Vec<Command> {
        let mut says = Vec::new();
        for event in events {
            if let Event::MentorAsked { account, question } = event {
                let met = self.met.get(account).cloned().unwrap_or_default();
                let (about, text) = answer(question, &met);
                says.push(say(account, about, text.to_string()));
                continue;
            }
            let Some((account, lesson)) = self.lesson_in(event) else {
                continue;
            };
            if is_person(&account) && self.met.entry(account.clone()).or_default().insert(lesson) {
                says.push(say(&account, lesson.about(), words(lesson).to_string()));
            }
        }
        says
    }

    fn lesson_in(&mut self, event: &Event) -> Option<(AccountId, Lesson)> {
        match event {
            Event::MealEaten {
                account,
                item,
                usdc,
                ..
            } => {
                let key = (account.clone(), item.clone());
                let before = self.last_paid.insert(key, *usdc);
                before
                    .filter(|paid| usdc > paid)
                    .map(|_| (account.clone(), Lesson::Inflation))
            }
            _ => None,
        }
    }
}

fn say(account: &str, about: &str, text: String) -> Command {
    Command::MentorSay {
        account: account.to_string(),
        about: about.to_string(),
        text,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn meal(usdc: Usdc) -> Event {
        Event::MealEaten {
            account: "sam".into(),
            item: "chai".into(),
            usdc,
            food: 1_000_000,
            energy: 50,
            from_ration: 0,
            reference: format!("meal at {usdc}"),
            tx: String::new(),
        }
    }

    #[test]
    fn each_lesson_names_its_term_last() {
        for lesson in ALL_LESSONS {
            let text = words(lesson).to_lowercase();
            let term = lesson.terms()[0];
            assert!(
                text.trim_end_matches('.').ends_with(term),
                "{lesson:?}: {text}"
            );
        }
    }

    #[test]
    fn a_question_about_something_not_met_never_names_it() {
        let nothing = BTreeSet::new();
        for question in ["explain inflation", "why did the price go up?"] {
            let (about, text) = answer(question, &nothing);
            assert_eq!(about, "reply");
            assert_eq!(text, NOT_YET);
        }
        assert_eq!(answer("hello", &nothing), ("reply", NOTHING_YET));
    }

    #[test]
    fn a_question_about_something_met_gets_the_plain_explanation() {
        let met = BTreeSet::from([Lesson::Inflation]);
        assert_eq!(
            answer("what's inflation?", &met),
            ("inflation", words(Lesson::Inflation))
        );
        assert_eq!(
            answer("hello", &met).0,
            "inflation",
            "it talks about what they've seen"
        );
    }

    #[test]
    fn a_dearer_meal_than_last_time_is_met_once_and_a_cheaper_one_isnt_news() {
        let mut mentor = Mentor::default();
        assert!(
            mentor.read(&[meal(1000)]).is_empty(),
            "the first meal sets the price"
        );
        assert!(
            mentor.read(&[meal(900)]).is_empty(),
            "cheaper isn't inflation"
        );
        let said = mentor.read(&[meal(1100)]);
        assert_eq!(
            said,
            [say("sam", "inflation", words(Lesson::Inflation).into())]
        );
        assert!(mentor.read(&[meal(1200)]).is_empty(), "said once");
    }

    #[test]
    fn a_failed_model_call_falls_back_to_the_plain_words() {
        let failed = words_from(Lesson::Inflation, |_| Err::<String, _>("the model is down"));
        assert_eq!(failed, words(Lesson::Inflation));
        let answered = words_from(Lesson::Inflation, |_| {
            Ok::<_, &str>("from the model".to_string())
        });
        assert_eq!(answered, "from the model");
    }
}
