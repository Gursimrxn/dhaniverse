//! Who may be called what. A name becomes an ENS label later, so it follows those rules now, and a name stays with
//! the secret that first claimed it.

use serde::Serialize;
use sha2::{Digest, Sha256};

const NAME_LENGTH: std::ops::RangeInclusive<usize> = 3..=20;
const SECRET_LENGTH: std::ops::RangeInclusive<usize> = 16..=128;
/// The town's own people and the ENS names its agents will hold.
const RESERVED: [&str; 10] = [
    "resident",
    "desk",
    "harbourmaster",
    "arthur",
    "kofi",
    "mei",
    "tally",
    "rates",
    "mentor",
    "admin",
];
// ponytail: whole words only, between dashes, so "assam" and "scunthorpe" pass. A short list stops the obvious; add a
// proper list if players get around it.
const RUDE: [&str; 16] = [
    "arse",
    "ass",
    "asshole",
    "bastard",
    "bitch",
    "chutiya",
    "cock",
    "cunt",
    "dick",
    "fuck",
    "madarchod",
    "nazi",
    "piss",
    "rape",
    "shit",
    "whore",
];

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
#[serde(tag = "type")]
pub enum HelloRefusal {
    BadName { name: String },
    NameTaken { name: String },
    BadSecret,
    SlowDown,
}

/// Everything about a `hello` that can be told without looking at who holds the name.
pub fn check_hello(name: &str, secret: &str) -> Result<(), HelloRefusal> {
    if !valid_name(name) || is_rude(name) {
        return Err(HelloRefusal::BadName {
            name: name.to_string(),
        });
    }
    if RESERVED.contains(&name) {
        return Err(HelloRefusal::NameTaken {
            name: name.to_string(),
        });
    }
    check_secret(secret)
}

pub fn check_secret(secret: &str) -> Result<(), HelloRefusal> {
    if !SECRET_LENGTH.contains(&secret.len()) {
        return Err(HelloRefusal::BadSecret);
    }
    Ok(())
}

/// Lowercase letters, digits and single inner dashes, as an ENS label.
fn valid_name(name: &str) -> bool {
    NAME_LENGTH.contains(&name.len())
        && name
            .bytes()
            .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == b'-')
        && !name.starts_with('-')
        && !name.ends_with('-')
        && !name.contains("--")
}

fn is_rude(name: &str) -> bool {
    name.split('-').any(|word| RUDE.contains(&word))
}

/// What the log keeps instead of the secret. Salted with the name, so two players' hashes never match.
// ponytail: one round of SHA-256 suits the long random secrets clients generate. If players ever type passwords, use
// argon2 here.
pub fn hash_secret(name: &str, secret: &str) -> String {
    let digest = Sha256::digest(format!("dhaniverse:{name}:{secret}"));
    digest.iter().map(|byte| format!("{byte:02x}")).collect()
}

#[cfg(test)]
mod tests {
    use super::*;

    const SECRET: &str = "0123456789abcdef";

    fn check(name: &str) -> Result<(), HelloRefusal> {
        check_hello(name, SECRET)
    }

    #[test]
    fn a_name_is_three_to_twenty_of_lowercase_digits_and_dashes() {
        for good in ["sam", "sam-2", "a1b", "twenty-characters-ok"] {
            assert_eq!(check(good), Ok(()), "{good}");
        }
        for bad in [
            "",
            "ab",
            "twenty-one-characters",
            "Sam",
            "sam_1",
            "sam!",
            "s m",
            "désirée",
        ] {
            assert!(
                matches!(check(bad), Err(HelloRefusal::BadName { .. })),
                "{bad}"
            );
        }
    }

    #[test]
    fn a_name_ens_would_refuse_is_refused_here_first() {
        for bad in ["-sam", "sam-", "sa--m"] {
            assert!(
                matches!(check(bad), Err(HelloRefusal::BadName { .. })),
                "{bad}"
            );
        }
    }

    #[test]
    fn rude_words_are_refused_but_names_that_only_contain_them_arent() {
        for bad in ["shit", "big-shit", "fuck-you"] {
            assert!(
                matches!(check(bad), Err(HelloRefusal::BadName { .. })),
                "{bad}"
            );
        }
        for fine in ["assam", "scunthorpe", "dickens"] {
            assert_eq!(check(fine), Ok(()), "{fine}");
        }
    }

    #[test]
    fn the_towns_own_people_are_taken() {
        assert_eq!(
            check("kofi"),
            Err(HelloRefusal::NameTaken {
                name: "kofi".into()
            })
        );
    }

    #[test]
    fn a_secret_must_be_a_real_one() {
        assert_eq!(check_hello("sam", ""), Err(HelloRefusal::BadSecret));
        assert_eq!(check_hello("sam", "short"), Err(HelloRefusal::BadSecret));
        let long = "x".repeat(129);
        assert_eq!(check_hello("sam", &long), Err(HelloRefusal::BadSecret));
    }

    #[test]
    fn the_hash_depends_on_both_name_and_secret_and_hides_the_secret() {
        let hash = hash_secret("sam", SECRET);
        assert_eq!(hash.len(), 64);
        assert!(!hash.contains(SECRET));
        assert_eq!(hash, hash_secret("sam", SECRET));
        assert_ne!(hash, hash_secret("priya", SECRET));
        assert_ne!(hash, hash_secret("sam", "fedcba9876543210"));
    }
}
