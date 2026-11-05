//! The town's feed: the posts, who reacted, and who follows whom. Nothing here touches money. What a post says is decided
//! elsewhere, from the events alone.

use crate::{is_person, AccountId, Event, Life, Refusal, SocialConfig};
use serde::Serialize;
use std::collections::{BTreeMap, BTreeSet, HashMap, HashSet, VecDeque};

#[derive(Clone, Debug, PartialEq, Eq, Serialize)]
pub struct Post {
    pub id: u64,
    pub day: u64,
    pub kind: String,
    pub text: String,
    pub about: Option<AccountId>,
    pub reactions: BTreeMap<String, u32>,
    #[serde(skip)]
    reacted: HashSet<AccountId>,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct Social {
    config: SocialConfig,
    posts: VecDeque<Post>,
    last_id: u64,
    following: HashMap<AccountId, BTreeSet<AccountId>>,
}

impl Social {
    pub fn new(config: SocialConfig) -> Self {
        Social {
            config,
            posts: VecDeque::new(),
            last_id: 0,
            following: HashMap::new(),
        }
    }

    pub(crate) fn publish(
        &mut self,
        day: u64,
        kind: String,
        text: String,
        about: Option<AccountId>,
    ) -> Vec<Event> {
        self.last_id += 1;
        let id = self.last_id;
        self.posts.push_back(Post {
            id,
            day,
            kind: kind.clone(),
            text: text.clone(),
            about: about.clone(),
            reactions: BTreeMap::new(),
            reacted: HashSet::new(),
        });
        while self.posts.len() > self.config.posts_kept {
            self.posts.pop_front();
        }
        vec![Event::FeedPost {
            id,
            day,
            kind,
            text,
            about,
        }]
    }

    pub(crate) fn react(
        &mut self,
        account: AccountId,
        post: u64,
        emote: String,
    ) -> Result<Vec<Event>, Refusal> {
        if !self.config.emotes.contains(&emote) {
            return Err(Refusal::UnknownEmote { emote });
        }
        let found = self.posts.iter_mut().find(|p| p.id == post);
        let Some(found) = found else {
            return Err(Refusal::UnknownPost { post });
        };
        if !found.reacted.insert(account.clone()) {
            return Err(Refusal::AlreadyReacted { post });
        }
        *found.reactions.entry(emote.clone()).or_insert(0) += 1;
        Ok(vec![Event::Reacted {
            post,
            account,
            emote,
        }])
    }

    pub(crate) fn follow(
        &mut self,
        account: AccountId,
        player: AccountId,
        life: &Life,
    ) -> Result<Vec<Event>, Refusal> {
        if account == player {
            return Err(Refusal::FollowingYourself);
        }
        if !is_person(&player) {
            return Err(Refusal::UnknownPlayer { account: player });
        }
        life.check_arrived(&player)?;
        let list = self.following.entry(account.clone()).or_default();
        list.insert(player.clone());
        Ok(vec![Event::Followed { account, player }])
    }

    pub(crate) fn unfollow(
        &mut self,
        account: AccountId,
        player: AccountId,
    ) -> Result<Vec<Event>, Refusal> {
        let removed = self
            .following
            .get_mut(&account)
            .is_some_and(|list| list.remove(&player));
        if !removed {
            return Err(Refusal::NotFollowing { player });
        }
        Ok(vec![Event::Unfollowed { account, player }])
    }

    // ------------------------------------------------------------ reads

    pub fn emotes(&self) -> &[String] {
        &self.config.emotes
    }

    /// The latest posts, oldest first.
    pub fn latest(&self, count: usize) -> impl Iterator<Item = &Post> {
        self.posts
            .iter()
            .skip(self.posts.len().saturating_sub(count))
    }

    pub fn following(&self, account: &str) -> impl Iterator<Item = &AccountId> {
        self.following.get(account).into_iter().flatten()
    }
}
