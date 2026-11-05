//! The quest book, read from `quests.toml`: every quest's title, story and steps. The words live there; what each kind
//! of step needs, and what a quest pays, live in the rules and `rules.toml`.

use crate::Refusal;
use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

/// The sponsored templates a campaign can choose. Each has its steps in the book.
pub const TEMPLATES: [&str; 4] = ["spice_run", "paint_sign", "town_pass", "hold_line"];

/// How a step gets done, and so who may say it's done.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum StepKind {
    /// Talk to someone. The client says when, with `QuestStep`.
    Talk,
    /// Go somewhere. The client says when, with `QuestStep`.
    Visit,
    /// The harbourmaster's cargo: done at once if the wallet holds it, otherwise when the campaign's advance lands.
    Cargo,
    /// A real Uniswap swap, sent with `Swap` and seen on chain.
    Swap,
    /// The quest token handed to the Spice Merchant, sent with `Deliver` and seen on chain.
    Deliver,
    /// The shop sign written on your ENS name, sent with `PaintSign` and seen on chain.
    Sign,
    /// The Town Pass: done when World ID says you're a person.
    Verify,
    /// Hold the quest token, checked on chain at random moments.
    Hold,
    /// Read the paper at the square on a day something happened. The client says when.
    Paper,
    /// Eat paid meals after taking the quest. Counted by the rules.
    Meals,
    /// Open Grandma's strongbox, once every other step is done. The client says when.
    Strongbox,
}

impl StepKind {
    /// Steps the client reports itself with `QuestStep`.
    pub fn client_says(self) -> bool {
        matches!(
            self,
            StepKind::Talk
                | StepKind::Visit
                | StepKind::Cargo
                | StepKind::Paper
                | StepKind::Strongbox
        )
    }
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct StepText {
    pub id: String,
    pub kind: StepKind,
    pub text: String,
    /// Where it happens, for the client's quest marker: a place or a person's name.
    #[serde(default)]
    pub place: String,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct QuestText {
    #[serde(default)]
    pub id: String,
    pub title: String,
    pub story: String,
    /// Steps may be done in any order, except that a `Strongbox` step is always last.
    #[serde(default)]
    pub any_order: bool,
    pub steps: Vec<StepText>,
}

#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct QuestBook {
    #[serde(default)]
    pub templates: BTreeMap<String, QuestText>,
    #[serde(default)]
    pub errands: Vec<QuestText>,
    #[serde(default)]
    pub mysteries: Vec<QuestText>,
    pub grandma: Option<QuestText>,
}

impl QuestBook {
    /// Refuses a book a quest could get stuck in: a missing template, a template without the step that proves it, a
    /// step the client couldn't report, two steps with one id.
    pub fn check(&self) -> Result<(), Refusal> {
        let bad = |problem: String| Err(Refusal::BadQuestBook { problem });
        let needs: [(&str, &[StepKind]); 4] = [
            (
                "spice_run",
                &[StepKind::Cargo, StepKind::Swap, StepKind::Deliver],
            ),
            ("paint_sign", &[StepKind::Sign]),
            ("town_pass", &[StepKind::Verify]),
            ("hold_line", &[StepKind::Hold]),
        ];
        for (name, kinds) in needs {
            let Some(text) = self.templates.get(name) else {
                return bad(format!("no template {name}"));
            };
            for kind in kinds {
                if !text.steps.iter().any(|s| s.kind == *kind) {
                    return bad(format!("{name} has no {kind:?} step"));
                }
            }
        }
        let house = self.errands.iter().chain(&self.mysteries);
        for text in house {
            if text.id.is_empty() || text.id.contains(':') {
                return bad(format!(
                    "{}: an errand or mystery needs an id without ':'",
                    text.title
                ));
            }
            if text
                .steps
                .iter()
                .any(|s| !s.kind.client_says() || s.kind == StepKind::Cargo)
            {
                return bad(format!(
                    "{}: house quests only have steps the client reports",
                    text.id
                ));
            }
        }
        if let Some(grandma) = &self.grandma {
            let last = grandma.steps.last().map(|s| s.kind);
            if last != Some(StepKind::Strongbox) {
                return bad("grandma ends with her strongbox".to_string());
            }
        }
        let all = self
            .templates
            .values()
            .chain(&self.errands)
            .chain(&self.mysteries)
            .chain(&self.grandma);
        for text in all {
            if text.steps.is_empty() {
                return bad(format!("{} has no steps", text.title));
            }
            let mut ids: Vec<&str> = text.steps.iter().map(|s| s.id.as_str()).collect();
            ids.sort_unstable();
            if ids.windows(2).any(|w| w[0] == w[1]) {
                return bad(format!("{} has two steps with one id", text.title));
            }
        }
        Ok(())
    }

    pub fn errand(&self, id: &str) -> Option<&QuestText> {
        self.errands.iter().find(|e| e.id == id)
    }

    pub fn mystery(&self, id: &str) -> Option<&QuestText> {
        self.mysteries.iter().find(|e| e.id == id)
    }
}
