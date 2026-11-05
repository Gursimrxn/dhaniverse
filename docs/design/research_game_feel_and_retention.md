# Game feel and retention: what the evidence supports


**Evidence labels**
- **[A] Strong:** peer-reviewed meta-analysis, or a large experiment or field dataset.
- **[B] Moderate:** a single or small study, or a company reporting its own numbers.
- **[C] Opinion:** a designer's account, a case study, or a critic's reading. Useful, but it proves nothing about retention.

**How much was read.** Each source was read in full, as an abstract, or as a search excerpt. Anything below full text is flagged as "abstract" or "excerpt". Section 6 lists what I looked for and could not read, so it is not cited.

**The founder's link.** [gamedev-cheatsheet.com](https://gamedev-cheatsheet.com/) has 34 concepts on rendering, game feel, systems and performance. It has nothing on onboarding, retention, core loops, audio or web games. Its tuning numbers are used in section 5.

**Three facts from this repo change the priorities**
- `server/rules.toml` sets `month_ms = 1200000`, so a month is 20 minutes of play. **A stranger cannot miss an EMI in their first 10 minutes.** The game's central consequence arrives after the window in which most people decide whether to stay.
- `game/export_presets.cfg` has only a Windows preset. **There is no web export**, though the spec requires browser play.
- `build/Dhaniverse.exe` is 219.9 MB, and `game/assets` is 313 MB on disk (town 102, buildings 91, characters 85). That is far over the browser limits in finding 5.1.

---

## 1. First session and onboarding

**1.1 Tutorials help unconventional games and do little for familiar ones. Text teaches less than experimenting. [A]**
- Source: [Andersen et al., CHI 2012](https://dl.acm.org/doi/10.1145/2207676.2207687), full text excerpts, 45,000+ players in 3 games. In complex Foldit, context-sensitive tutorials raised play time 29% and levels completed 75%. Instructions given at the moment of need beat an up-front manual (+16% time, +40% progress). In the two simpler games tutorials had no real benefit, and one lost 3.5% of returning players. There was no evidence that restricting player freedom helps. A help button cut play time 15% in one game and raised it 12% in Foldit. The authors warn these were not commercial games.
- Do: treat Dhaniverse as nearer Foldit, because EMIs and repricing are unfamiliar. Give one short line at the moment of need, in the world. Don't lock players into a guided path.
- Stop: assuming "the mentor is one key away" is safe. On-demand help was harmful in one game and helpful in another, so watch whether it is used and whether users then quit.

**1.2 Watching strangers in silence is the most consistent practice among the teams that got this right. [C, but very consistent]**
- Source: [Birdwell on Half-Life](https://www.gamedeveloper.com/design/the-cabal-valve-s-design-process-for-creating-i-half-life-i-): 200+ two-hour sessions, observers forbidden to speak, about 100 action items per session. [Swift et al. on Portal](https://www.gamedeveloper.com/design/thinking-with-portals-creating-valve-s-new-ip): a new tester each week from week one. [Portal at GDC 2008](https://www.gamedeveloper.com/pc/best-of-gdc-the-secrets-of-i-portal-i-s-huge-success): Swift called playtesting probably the most important thing they did, and advised watching rather than reading reports.
- Do: run at least 5 silent sessions with strangers before the first phase, starting now, and use a clean browser or machine. The founder's verdict came from watching a bot, and a bot can't show confusion.
- Do: copy Portal's closing test, "tell us the story back". Ask "what did the debt cost you, and why?" This is the spec's success measure, run as a method.

**1.3 Break a stuck concept into smaller rooms instead of explaining it. [C]**
- Source: [Swift et al.](https://www.gamedeveloper.com/design/thinking-with-portals-creating-valve-s-new-ip): testers stuck on a double energy-ball redirect grasped it quicker once it was split into single-redirect rooms. [GDC 2008 coverage](https://www.gamedeveloper.com/pc/best-of-gdc-the-secrets-of-i-portal-i-s-huge-success): a shimmering force field confused players, so it became plain glass, and the world was simplified over time.
- Do: if players don't follow the first EMI, split it: first a small debt you can clear, then a monthly one. Replace ambiguous props rather than adding labels.

**1.4 The game must respond to everything the player does, densely, and only when they act. [C]**
- Source: [Birdwell](https://www.gamedeveloper.com/design/the-cabal-valve-s-design-process-for-creating-i-half-life-i-): short gaps between stimuli ("experiential density"), "the game world must acknowledge players every time they perform an action", and "no activities are started outside the player's control". Failure should feel fair, with hints of danger and a way out.
- Do: this is the direct cure for "hardcoded". Residents glance up when you pass, Kofi comments on your first order, and your stall's state changes. Trigger beats by the player's position or action rather than by a timer.
- Stop: the spec's "slow camera... control fades in as you step off" if the wait is long. Let the player walk the ferry deck within about 10 seconds, with an instant skip. The 10 seconds is my judgement. No source gives a number.

**1.5 Autonomy, competence and relatedness each predict enjoyment and further play. [A, abstract summary only]**
- Source: [Ryan, Rigby & Przybylski 2006](https://doi.org/10.1007/s11031-006-9051-8), four studies, 3,300+ citations.
- Do: it supports "sign or walk away" as a real choice. It makes a useful test for every first-session beat: did the player choose, get better, or connect? Cut any beat that does none of these.

**1.6 Naming: identifying with your character raises motivation. Asking in conversation is a proven pattern, but not a proven effect. [B for identification, C for the method]**
- Source: [Birk et al., CHI 2016](https://doi.org/10.1145/2858036.2858062), summary only: identification raised autonomy, immersion, effort and enjoyment. [Nookipedia on Rover](https://nookipedia.com/wiki/Rover): in the original Animal Crossing, a stranger's questions on the train set your gender and appearance. I found no study that compares a dialogue prompt with a form.
- Do: Rosa asks for the name on her card, as the spec says. Then pay it off within seconds: on the letter, on the stall sign, and in the first thing a resident calls you. No confirmation screen.

**1.7 Animal Crossing's debt: a strong structure, no retention data, and Nintendo itself grew tired of it. [C]**
- Source: [Wikipedia, citing Eguchi and Bogost](https://en.wikipedia.org/wiki/Animal_Crossing_(video_game)): pay off, expand, owe again. The origin was Eguchi's memory of moving to Kyoto and slowly furnishing an empty home. [Iwata Asks: New Leaf](https://iwataasks.nintendo.com/interviews/3ds/animalcrossing-newleaf/0/0): Iwata said core play boiled down to paying off debt, and the team reset the formula to avoid players groaning at routine.
- Do: copy the shape. Each repayment visibly upgrades something you own and opens the next want. Flats after the stall debt fit this exactly.
- Caution: I could not confirm Nook's loan terms from what I read. Don't argue "Animal Crossing proves debt hooks": no data shows it. Dhaniverse's debt has real teeth, which is untested as a hook.

**1.8 Breath of the Wild: a small safe world that holds the whole game in miniature. [C]**
- Source: [The Guardian](https://www.theguardian.com/technology/2017/may/30/the-legend-of-zelda-breath-of-the-wild-nintendo-game-design-open-world-player-explore), excerpt: the Great Plateau works as a miniature world instead of a tutorial mission. [80.lv on CEDEC 2017](https://80.lv/articles/the-design-secrets-of-breath-of-the-wild/), secondary: triangular terrain offers over-or-around choices and hides what lies beyond. [Reeve](https://www.gamedeveloper.com/design/breath-of-the-wild-s-montessori-method), a critic's reading: harmless trial and error, and lost hearts are returned.
- Do: make the landing Dhaniverse's plateau: stall, Rosa, Kofi, bed and bank door within one view. Use sightlines to pull the player on: the bell tower or the Homes' courtyard half hidden behind a roofline.

**1.9 Stardew Valley: the letter is close to our opening, and even its praise admits early confusion. [C]**
- Source: [GQ profile](https://www.gq.com/story/stardew-valley-eric-barone-profile), excerpt: a grandfather's letter hands over the deed and the responsibility. [GameSpew review](https://www.gamespew.com/2016/03/stardew-valley-review/): "confused" for the first days, helped by gifted seeds and a quest to meet everyone. [NPR](https://www.npr.org/2025/01/24/g-s1-44510/the-legacy-and-future-of-the-farming-game-stardew-valley): Barone wanted relaxed pacing rather than hyper-stimulation. [Inc](https://www.inc.com/ben-sherry/with-stardew-valley-eric-barone-makes-entrepreneurship-enchanting-his-own-business-isnt-his-concern.html): players turn a vision into their own to-do list.
- Do: keep the letter very short. Stardew's fits on a page, and it follows a scene that made you want to leave your old life. Give the player something in hand at once, such as a first order or the stall key.
- Note: the grandparent-inheritance opening will read as a Stardew echo to anyone who knows it. Either own that or change the relative. The hook is the debt, which Stardew's letter does not have.

**1.10 EVE: most new players left within hours, and CCP's own answer was "care first, systems later". [B, company figures via press]**
- Source: [Destructoid, 2016](https://destructoid.com/?p=206617): 1.5M+ sign-ups in a year, the overwhelming majority gone permanently after two hours. CCP planned story and emotional investment before systems, and Nordgren wanted new players to feel they were playing, not completing a tutorial. [Kotaku, 2019](https://kotaku.com/eve-online-developers-discuss-ways-to-stop-new-players-1835909279): about 10% remained after a week. Losing a first ship was treated as a defining moment, so a Game Master would explain it and might restore the ship once.
- Do: this is the closest warning: a deep player economy doesn't rescue a poor start. Give the first missed EMI the same treatment: someone comes to you, explains it, and shows the way back, once.

**1.11 Baselines for scale. [B, summaries of an industry report]**
- Source: [GameAnalytics 2026 summary](https://gamedevreports.substack.com/p/gameanalytics-mobile-and-pc-game): median D1 about 22%, top quartile just over 30%, median D7 just under 4%. Summaries disagree on the top-end figures.
- Do: a build build won't have these numbers. Measure the funnel instead: load finished, moved, named, chose, first coin, first close, returned. Those events can be logged by the server you already have.

---

## 2. Core loops and why people return

**2.1 Loops build understanding, and arcs deliver a thing once. [C, the clearest framing available]**
- Source: [Daniel Cook, Loops and Arcs](https://www.lostgarden.com/2012/04/loops-and-arcs): loops "deliver value through the act of being exercised" and build a holistic understanding of a system. An arc's value drops sharply on repeat, and arcs are almost never critical.
- Do: this names the founder's complaint. The current build is an arc wearing a game's clothes: a fixed sequence that plays once. Write down the loop at each timescale and test whether each works with the story removed. **Moment:** serve, earn, react. **Session:** shift, spend, decide. **Month:** close, consequence, new want. **Season:** shock, leaderboard, reset.

**2.2 Build the loop first, then progression, social and live ops. [C, Scopely's own account]**
- Source: [Mobilegamer on Monopoly Go](https://mobilegamer.biz/scopelys-monopoly-go-three-years-of-iterating-to-greatness-and-one-big-pivot/): Scopely dropped synchronous PvP because players wanted to play with friends and family, then "built the core loop, then the progression system, social layers and live operations". Pressing one big button starts wealth accumulating, testing what the brand was emotionally about. Staff listed 100 feelings about the game to find details to fix.
- Do: the spec ranks people above the loop, and calls minigame variety a later concern. Keep the priority for the demo, but give a stranger's first shift a real moment-to-moment verb now, because they spend most of the first 10 minutes in it.
- Do: keep social interaction asynchronous. Nothing should need two people online at once, which the spec's goal 5 already implies.
- Stop: copying Monopoly Go's dice economy. [Sensor Tower's reading](https://investgame.net/wp-content/uploads/2025/12/2025-12-17-STChanceBasedMonopolyGO.pdf) (excerpt) describes it as near-depletion and lucky spikes. That's a monetisation tool, and it teaches gambling in a game about money.

**2.3 A zero-sum system can punish progress, and a fresh competitive cycle fixes it. Casual passes reach everyone. [B, secondary notes on a Supercell talk]**
- Source: [EGD notes on Eino Joas's talk](https://elitegamedevelopers.substack.com/p/egd-news-49-problems-with-old-f2p-mid-core-games-2): in Clash of Clans, upgrading made opponents tougher, so "chances of winning went down as you leveled up" and players stopped upgrading. Monthly start-stop leagues broke the stalemate. Gold Pass tasks complete casually in the player's own style. Revenue and payer figures were reported, not retention. The [GDC Vault listing](https://gdcvault.com/play/1026741/-Clash-of-Clans-Bigger) has the talk.
- Do: test the rules for this trap: does buying a flat ever worsen your board position? Keep the season reset. Make weekly goals things players complete by playing their own way.

**2.4 The world as the main character. [C, a designer's belief, disputed inside Epic]**
- Source: [Mustard on Fortnite](https://www.sportskeeda.com/esports/the-world-fortnite-main-character-donald-mustard-explains-storyline-chapter-2-season-6): the world has an arc, and players often see only "the results of it happening around you". [Aftermath interview](https://aftermath.site/fortnite-donald-mustard-interview/): live events were "the magic", and "not everyone at Epic agrees". They faded for lack of resources. I found no study on why players return.
- Do: leave visible marks from rate hikes and seasons that stay: a closed shop, a sold sign, a new block. Show the aftermath more than the event. It's cheaper than a cutscene too.

**2.5 EVE's economy: real prices make stories, but they are not the retention engine. [C]**
- Source: [CCP's economist appointment](https://community.eveonline.com/news/news-channels/press-releases/eve-online-appoints-in-world-economist-1), excerpt. [Kotaku](https://kotaku.com/eve-online-developers-discuss-ways-to-stop-new-players-1835909279): CCP credited players with making the game legendary. I did not find a primary source on B-R5RB or a retention study on social ties, so I don't claim either.
- Do: publish a short, real monthly town report through the paper. It is cheap, it fits the Tally, and it creates the stories. "Numbers come from the server" is already the rule.

**2.6 The Sims: a problem landscape, and needs linked to aspirations. [C, thin]**
- Source: [Wikipedia](https://en.wikipedia.org/wiki/The_Sims), excerpt: Wright sets a problem landscape and solution space for players to roam. [Wright's MasterClass outline](https://www.masterclass.com/classes/will-wright-teaches-game-design-and-theory/chapters/exploring-player-psychology), excerpt: base motives connect to larger aspirations.
- Do: connect energy and food (base) to rent and home (middle) to the title and landlord status (top), so that a meal feels connected to owning a flat. The current well-fed bonus is a start.

**2.7 Disco Elysium: mistakes are expected and don't lock you out. [C, one excerpt]**
- Source: [Kurvitz via PC Invasion](https://pcinvasion.com/?p=194289), excerpt only. A source I could not open directly. It reports that mistakes aren't punished by loss of access to content.
- Do: every bad money outcome should open something: the bank's letter, Rosa's reaction, a cheaper room, a new thread. A failure with no new content is just a penalty. This agrees with the spec's "never ruined".

**2.8 Progress that's already started pulls people forward. [B, secondary only]**
- Source: Nunes & Drèze 2006, [JCR](https://doi.org/10.1086/500480), read only through [a secondary summary](https://coglode.com/nuggets/endowed-progress-effect): car-wash cards with 2 of 10 stamps pre-filled beat 8-stamp cards, though both needed 8 washes. I could not read the original's exact percentages.
- Do: show the ladder with Worker partly filled, or the stall's repair list with two items already done by grandmother. A low-cost, honest effect.

---

## 3. Learning through play

**3.1 Games teach modestly better than conventional teaching. They aren't automatically more motivating. [A]**
- Source: [Wouters et al. 2013](https://doi.org/10.1037/a0031311), learning d=0.29, retention d=0.36, motivation not significantly higher. Results were better with supplementary instruction, multiple sessions and group play. [Clark et al. 2016](https://doi.org/10.3102/0034654315582065), g=0.33 for games over non-games, and g=0.34 for better over plainer game designs.
- Do: the gains favour the spec's own structure: returning sessions, other people, and a mentor or paper that names the thing afterwards. Don't remove the naming step in the name of stealth.

**3.2 Put the learning inside the core mechanic. This is the best direct evidence on chocolate-covered broccoli. [B: strong design, small samples, children]**
- Source: [Habgood & Ainsworth 2011](https://doi.org/10.1080/10508406.2010.508029): children aged 7-11 learned more from the intrinsic version under fixed time (n=58), and played it 7 times longer given free choice (n=16).
- Do: money must be how you act, not a quiz between actions. Test each feature: remove the finance and does the mechanic still exist? If a screen can be dropped with no effect on play, it's broccoli.

**3.3 Struggle first, name it after: well supported, with an age limit. [A]**
- Source: [Sinha & Kapur 2021](https://doi.org/10.3102/00346543211019105), 53 studies, g=0.36 favouring problem solving before instruction, stronger with careful design. Results reversed for second to fifth graders.
- Do: it directly supports "consequence first, word second", for a young-adult audience. The naming step still has to happen: the method depends on instruction following the struggle.

**3.4 People learn from paying a penalty, fast, and then forget. This is the most relevant finding here. [A: four million statements]**
- Source: [Agarwal et al., NBER w13822](https://doi.org/10.3386/w13822): paying a fee cuts the chance of paying one next month by about 40%, and fee payments fall 75% in three years. Knowledge depreciates about 10% a month.
- Do: this is real-world evidence for the pitch. Note the mechanism: the penalty is immediate, specific and personal. Vary and repeat consequences, because a single miss will fade.
- Do: use this line in the pitch instead of claiming the game changes behaviour. See 3.6.

**3.5 Quick, specific feedback outperforms delayed, vague feedback. [B, Riot's own figures in a good outlet, different domain]**
- Source: [Scientific American on Riot](https://www.scientificamerican.com/article/can-a-video-game-company-tame-toxic-behavior/): detailed reform cards raised no-repeat rates from 50% to 70%. Feedback within 5-10 minutes of an offence reached 92%.
- Do: another reason a 20-minute first month is too slow. Show the exact chain at the close: "you earned X, EMI Y, you had Z". The player should be able to find the moment it went wrong.

**3.6 Do financial education and financial games work? Contested for education, and thin for games. [Mixed; say so]**
- Source: [Fernandes et al. 2014](https://doi.org/10.1287/mnsc.2013.1849), summary: 201 studies, interventions explain 0.1% of variance in behaviour. [Kaiser et al.](https://www.nber.org/papers/w27057), 76 randomised trials, 160,000+ people: positive effects on knowledge and behaviour, at least three times earlier estimates. The newer, randomised-only result is more credible, but the debate stands.
- Source on games: [Lima da Silva Moraes et al. 2026](https://library.iated.org/view/LIMADASILVAMORAES2026GAM), abstract: 28 studies, positive with substantial heterogeneity, no pooled value in the abstract, conference paper. [Carlin & Robinson](https://doi.org/10.3386/w16271), role-play with assigned life situations: strong effects, and students also used decision support more. Yet trying to save more often led to poor choices when spending more today was cheaper in present value. I could not read the Farm Blitz trial's results.
- Do: tell people the honest version: experiential learning has support, and evidence for financial games specifically is thin. Don't claim the game raises real savings.
- Do: take Carlin & Robinson's warning seriously. See 3.8.

**3.7 Easier keeps people playing, and teaches less. [A for engagement, two large experiments, one maths game]**
- Source: [Lomas et al., CHI 2013](https://doi.org/10.1145/2470654.2470668), 10K and 70K players: easier was almost always more engaging, and the most engaging designs produced the slowest learning.
- Do: expect this to be a real trade-off in tuning. Start gentle so strangers stay, then let the player choose harder: a bigger loan is a difficulty setting they opted into.

**3.8 The "other you" has direct support and a direct risk. Both matter. [A/B]**
- For: [Hershfield et al. 2011](https://doi.org/10.1509/jmkr.48.SPL.S23), abstract, four studies: meeting a rendering of your future self raised preference for later money. Used VR and aged faces, so it doesn't transfer automatically. I did not check replications.
- Against: [Beshears et al. 2015](https://www.hks.harvard.edu/publications/effect-providing-peer-information-retirement-savings-decisions-0), field experiment: showing low savers that peers saved more **reduced** savings in one group, attributed mainly to discouragement from upward comparison.
- Also: [Carlin & Robinson](https://doi.org/10.3386/w16271) showed a "save more" lesson can overcorrect.
- Do: always pair the ghost with one reachable next step: "start with 1 order's pay". Keep the gap small by comparing the last few months as well as the total. It should never read as a score.
- Do: don't make it always "saved 10%". If debt costs more than savings earn, the better twin paid down the debt. A fixed-savings ghost would then teach a false lesson in a game about money. *This is my inference from the sources.*

**3.9 Consequences in play: experience and description give different lessons. [A/B]**
- Source: [Hertwig et al. 2004](https://collaborate.princeton.edu/en/publications/decisions-from-experience-and-the-effect-of-rare-events-in-risky-/), abstract fragments: people underweight rare events they learn about from experience. [Malmendier & Nagel](https://www.nber.org/papers/w14813): people who lived through poor returns take less financial risk, and recent experience counts most, on real survey data.
- Do: a player who never meets a rate shock will learn "rates don't move". Seasons must guarantee the shock, and the feed must show it hitting others. Don't let the crash be the only share experience, or the game teaches "never invest". Let each player see a recovery too.

**3.10 Loss aversion: use with caution. It's less settled than popular accounts. [Contested]**
- Source: [Gal & Rucker 2018](https://papers.ssrn.com/abstract=3049660), excerpt: much evidence is ambiguous. [Mrkva et al. 2020](https://researchportal.bath.ac.uk/en/publications/moderating-loss-aversion-loss-aversion-has-moderators-but-reports/), excerpt: it has moderators, and reports of its death are exaggerated.
- Do: don't build the design on "losses hurt twice as much". What is well evidenced is 3.4: paying a penalty changes behaviour. A consequence that merely threatens may not do the same. Let the miss really happen.

---

## 4. Social and competitive design

**4.1 Public competition can reduce motivation, and it depends on design. [A/B]**
- Source: [Hanus & Fox 2015](https://doi.org/10.1016/j.compedu.2014.08.019), summary: a gamified course had lower motivation, satisfaction and empowerment over time than a plain one. [Jia et al., CHI 2017](https://doi.org/10.1145/3025453.3025826), summary: preferences vary with rank, domain and personality.
- Do: treat the leaderboard as a feature with risk, and test it on low-ranked players, not just on the winner.

**4.2 Low ranks are not always demotivating, and high ranks can make people coast. [B, single small study]**
- Source: [Internet Research 2022](https://www.emerald.com/insight/content/doi/10.1108/intr-12-2021-0897/full/html): 111 students with ranks fixed high or low over 5 rounds. High ranks showed complacency, low ranks worked harder but dropped at the end, and neither looked intrinsically motivated. No real stakes, and a narrow score gap.
- Do: keep gaps small and visible, and let people move. The likely condition for working is a reachable next rank.

**4.3 Leagues of similar people, automatic and reset: the best commercial evidence. [B, the company's own account]**
- Source: [Duolingo growth write-up](https://www.lennysnewsletter.com/p/how-duolingo-reignited-user-growth): users are matched with people of similar prior-week engagement and move through tiers, opted in with no extra tasks. Learning time rose 17%, highly engaged learners tripled, and D1 and D7 improved. Streak features took 7-day-plus streaks from a small share to over half of DAU, with streak freezes among the iterations. A habit app is not a life-sim.
- Do: replace "top 10 plus your rank" with **your neighbours: two above, two below, you**, with the top 3 as a small header. In a season, group by join date, so a newcomer's first board is winnable. No opt-in.
- Do: the spec's four boards are good. Show each player the board on which they rank highest. Fastest climber and most stable give newcomers a real shot.

**4.4 Telling people the norm moves those above it down, unless you approve of them. [A, a classic field experiment]**
- Source: [Schultz et al. 2007](https://doi.org/10.1111/j.1467-9280.2007.01917.x), read through [authors' reprise](https://www.scranton.edu/faculty/nolan/pdfs/social-norms-reprise_perspectives_schultz-et-al2018.pdf) and summaries: households using less than average increased use when told the average. A smiley for approval removed the effect.
- Do: stable players need recognition, not a number: a title, a nod from Rosa, or a line in the paper. Don't publish averages like "the town saves 14%" without approval attached.

**4.5 Being surrounded by others matters, even with little direct interaction. [B, observational, WoW]**
- Source: [Ducheneaut et al., "Alone Together?"](https://doi.org/10.1145/1124772.1124834), summary: social activity in MMOs was less than assumed. [Ducheneaut & Yee](https://www.sri.com/publication/fcd-publications/collective-solitude-and-social-networks-in-world-of-warcraft/): players play "surrounded by, but not necessarily with" others, and networks are sparse.
- Do: this supports presence over chat. Bodies in the square, names, and the emotes in the feed may be enough. Don't invest in deep social systems yet.

**4.6 Friendship needs proximity, similarity, reciprocity and safe disclosure. [C, drawing on social science]**
- Source: [Cook, Game Design Patterns for Building Friendships](https://www.lostgarden.com/2017/01/game-design-patterns-for-building): anti-patterns include weak player identification, early zero-sum play, extreme power gaps and premature disclosure. He recommends shared recurring events, hubs, and human scale.
- Do: the bell is your hub. Gather people at the square at the month's shared moment. Offer one tiny reciprocal action early: a resident or player's "nice stall" emote that can be returned. A small, safe entry. Keep the public-tier rules on money, which match the anti-pattern list.

**4.7 Reputation works best as quick, specific, mostly positive feedback, for ordinary people. [B, Riot's own figures]**
- Source: [Scientific American](https://www.scientificamerican.com/article/can-a-video-game-company-tame-toxic-behavior/): 1% of consistently toxic players made about 5% of toxicity; most came from ordinary people on a bad day. Honor exists, with no measured effect in this article. [Red Bull](https://www.redbull.com/us-en/league-of-legends-the-good-behavior-game) covers the same talk.
- Do: emote-only feeds avoid most of this. Use a small positive set, with no downvote. Reputation labels should come from conduct: paid on time, fair landlord. Let people earn their way out.

**4.8 Competition appeals most to the young. Target fit is good. [B, survey via excerpt]**
- Source: [Quantic Foundry](https://quanticfoundry.com/2016/08/11/appeal-of-competition/), excerpt, as the page blocked direct reading: 140,000+ profiles. Competition declines most with age, mostly between 13 and 35. Self-selected survey respondents.
- Do: this is a reason to keep the competitive layer for young players, not evidence it will work.

**4.9 Hide the social layer for the first few minutes. [B]**
- Source: [Andersen et al., FDG 2011](https://doi.org/10.1145/2159365.2159370), summary, and [Andersen et al., CHI 2011](https://grail.cs.washington.edu/projects/game-abtesting/chi2011/): secondary objectives and optional rewards reduced play for many players, unless they support the primary goal. In one game this mattered about three times more than the largest aesthetic change.
- Do: boards, firsts, titles and four rankings are secondary objectives. Reveal them after the first close, tied to what the player just did. "You moved up one" is the first time a stranger should see a board. The person walking past is visible from the start.

---

## 5. Cinematic direction and the browser

**5.1 Browser size limits are real and we are far over them. [B: portal rules are facts, drop-off from video data]**
- Source: [CrazyGames requirements](https://docs.crazygames.com/requirements/technical/): initial download at most 50 MB, 20 MB for the mobile homepage, 250 MB total, and for externally hosted files, about 20 seconds to gameplay. [Krishnan & Sitaraman 2013](https://groups.cs.umass.edu/ramesh/wp-content/uploads/sites/3/2019/12/Video-stream-quality-impacts-viewer-behavior-inferring-causality-using-quasi-experimental-designs.pdf), excerpt, 6.7M viewers: abandonment begins after 2 seconds of startup delay, and rises 5.8% each extra second. That's on-demand video, not games, and people likely wait longer for a game. I found no published load-time drop-off curve for browser games.
- Do: split the pack. The first `.pck` holds only the ferry and the landing, aiming for under 50 MB compressed. Load the rest behind the arrival. The ferry is a strong natural loading moment, since the player is on a boat and the town approaches.
- Do: audit the 313 MB: 102 MB of town and 91 MB of buildings probably contain more textures than the camera shows. The cheat sheet's atlas, LOD and instancing notes apply.
- Do: show a real progress bar on the page before Godot starts, on the brand background. Measure load time on a mid-range laptop on home Wi-Fi, not on the dev machine.

**5.2 Godot web has specific traps for this game. [A: official docs]**
- Source: [Godot: exporting for the web](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html): the Compatibility renderer is required (already set). Single-threaded is the default. Threads need COOP/COEP headers or the PWA workaround, or the project won't run. WASM gzips to about a quarter of its size, and itch.io doesn't compress on the fly. Safari has WebGL 2 issues. [Godot: optimising for size](https://docs.godotengine.org/en/stable/engine_details/development/compiling/optimizing_for_size.html): custom templates help, but numbers are only given for a few options.
- Do: **the default Sample audio mode lacks reverb, doppler and procedural audio.** The spec's generated month bell may not play in the browser. Bake the bell and any generated sound to files now.
- Do: create the web preset today and test it daily, because a late first web build is the project's largest hidden risk. Serve with Brotli or gzip, and set the headers on your own host. Recommend Chrome or Edge in the page, for the demo.

**5.3 Moderate feedback beats none and beats extreme. [A/B, largest study of its kind, action RPG]**
- Source: [Kao 2020](https://doi.org/10.1016/j.entcom.2020.100359), N=3,018: both no juice and extreme juice lowered play time, experience, motivation and performance compared with medium and high.
- Do: **this conflicts with the standing "minimal motion" rule.** Calm brand doesn't need no feedback. Keep the HUD calm, and give each order, coin and payment a small but clear response. Founder's call. *A life-sim may differ from an action RPG.*
- Use: [cheat sheet](https://gamedev-cheatsheet.com/) values: about 0.3 s easing for UI, easeOutBack for slight overshoot, 0.1-0.2 s to reach full walking speed, trauma-based shake, used for the rate-hike bell only.

**5.4 Sound: less evidence than people assume. It is still worth a small, focused budget. [B, against the spec's wording]**
- Source: [Andersen et al., CHI 2011](https://grail.cs.washington.edu/projects/game-abtesting/chi2011/): in two Flash puzzle games, music and sound effects had little effect on staying or returning, while animations raised play time.
- Do: the study is narrow and doesn't test atmosphere, a 3D town or a judge in a room, so it doesn't overturn "sound is required". It does change the order: **coin, paper and bell first; ambience per place second; one music track third.** Don't spend days on a score. Sound's value for the demo is my judgement, not a finding.

**5.5 Camera: invisible when right. [C]**
- Source: [Nesky's GDC 2014 talk, via Game Developer](https://gamedeveloper.com/design/video-50-common-game-camera-mistakes----and-how-to-fix-them): "Cameras are most noticeable when they fail". I read the summary, not the 50 items. [Cheat sheet](https://gamedev-cheatsheet.com/): a deadzone about a quarter of the screen wide, moving only by the excess.
- Do: watch the 50 mistakes talk before filming camera paths. Fix the follow camera before building any cutscene, because players look through it for all 10 minutes and through a cutscene for seconds.

**5.6 Small-budget cinema: cut, don't animate. [C, excerpts only]**
- Source: [Thirty Flights of Loving](https://en.wikipedia.org/wiki/Thirty_Flights_of_Loving) and [Thinkwell's analysis](https://thinkwellgroup.com/?p=19100), excerpts: a one-developer game known for hard cuts and time jumps, building on Half-Life's continuous approach. [Blendo](https://www.blendogames.com/about.htm) confirms the small team. [Swift et al.](https://www.gamedeveloper.com/design/thinking-with-portals-creating-valve-s-new-ip): Portal had no time for human characters, so GLaDOS came from a text-to-speech test, and became one of its strongest parts.
- Do: use hard cuts with audio carrying across, instead of long camera moves through a town that may not hold up from every angle. Month end could be 4 fixed shots and a bell, not a time-lapse system. Constraints can make the character: Rosa can stay mostly off camera if the voice lands.
- Stop: tying every moment to a transition through the Dhaniverse mark, if it adds seconds on repeat. Monthly events must be skippable after the first time. *My inference.*

**5.7 Story testing beats story writing. [C]**
- Source: [GDC 2008 coverage](https://www.gamedeveloper.com/pc/best-of-gdc-the-secrets-of-i-portal-i-s-huge-success): story should never contradict gameplay, the team trimmed to align them, and asked players to tell it back. [Swift et al.](https://www.gamedeveloper.com/design/thinking-with-portals-creating-valve-s-new-ip): the game went dry at 15-30 minutes, so a writer was brought in, and voice lines became the incentive to continue.
- Do: Dhaniverse needs its hook at the likely dry point. The grandmother's thread should give the next clue around the first close, in a mail arrival with a real choice. One letter and one follow-up, as the spec limits, is enough if they fall there.

**5.8 Residents at scale. [Facts from the cheat sheet, not evidence on retention]**
- Source: [Cheat sheet](https://gamedev-cheatsheet.com/): time-slice agent decisions into 4-8 buckets, Y-axis billboards for name tags, instancing for repeated meshes, 16.67 ms frame budget.
- Do: use these for 30 players plus residents on single-threaded web. Test frame rate with the crowd on the target laptop before adding more.

---

## 6. What I looked for and could not support

- **GTA V's opening:** I read nothing primary or strong on the prologue's design. Rockstar's interviews found were about the three leads. **No claim is made.**
- **Half-Life's tram:** Birdwell's article, as read, doesn't cover the opening. The rules in 1.4 are general.
- **Clash of Clans' 2015 deck** could not be text-read, and **Disco Elysium** rests on one excerpt. No failure-as-content source was read directly.
- **Video-rental fines (Haselhuhn et al.)** and **Ruggeri et al. 2020 on loss aversion** could not be read, and are left out.
- **Farm Blitz trial results** were not retrievable. Only its design was confirmed: about 200 low-to-moderate income adults, game versus reading material.
- **No study found** compares name dialogue to forms, measures cold opens or cutscenes on retention, gives browser-game load drop-off curves, or tests a game like this one: multiplayer, 3D, with real consequences for personal finance. All first-minute time targets here and in the spec are judgement.

---

## 7. Top 15 changes for a stranger's first 10 minutes

The order is my judgement, built from the findings above. No study ranks them. Top items are ones where the stranger otherwise never reaches the good part.

| # | Change | Why | Evidence | Finding |
|---|---|---|---|---|
| 1 | **Ship a real web build:** add the preset, keep a first pack under 50 MB, load the rest behind the ferry, test daily | No preset exists, and the exe is 219.9 MB. A stranger on the website gets nothing otherwise | Portal rules, Godot docs: firm. Drop-off: video data | 5.1, 5.2 |
| 2 | **Make the first month close by about minute 7-8,** then run later months at normal length | At 20 minutes, the core lesson falls outside the window. Needs a rules and contract check | Penalty learning: A. Feedback timing: B. The number is judgement | 3.4, 3.5 |
| 3 | **Give control on the ferry within about 10 s,** with instant skip. Move the title over play | Removes passive time. Sets the expectation that the world responds to you | C, consistent | 1.4 |
| 4 | **Run 5 silent stranger tests now, with a tell-back at the end.** Repeat weekly | Finds what no research here can. A bot can't look confused | C, very consistent | 1.2 |
| 5 | **Make the shift a real moment-to-moment verb,** with unscripted customers | Most of the first 10 minutes happens here. This is the "steps" complaint | C | 2.1, 2.2 |
| 6 | **Make every action answered:** a coin, a look, a line, a small visual response. Relax "minimal motion" for feedback | "Hardcoded" is partly a world ignoring you | Juice: A/B. Rule: C | 1.4, 5.3 |
| 7 | **Delete step prompts,** and give one in-world line at the moment of need. Split stuck concepts into smaller beats | Text and restriction didn't help. Context did | A | 1.1, 1.3 |
| 8 | **Show money through play only,** with no finance screen in the first session that a player can skip with no effect | Tests "banking app with a 3D skin" directly | B | 3.2 |
| 9 | **Give the first miss a visit and a way back:** someone comes, shows the exact chain, then names it | Where the lesson lands, and where EVE lost people | Struggle-first: A. Follow-up: B/C | 3.3, 1.10, 2.7 |
| 10 | **Pay off the name and the signature in seconds:** the stall sign, a greeting, a stall state that differs by choice | Makes the first choice feel real | B/C | 1.5, 1.6 |
| 11 | **Make the landing a plateau:** a compact view with everything needed, the next want half hidden | Fewer wrong turns, without arrows | C | 1.8 |
| 12 | **Have people visibly doing things nearby from the first minute,** with boards and rankings hidden until the first close | Presence early, secondary goals later | B | 4.5, 4.9 |
| 13 | **Reframe the other you:** show a reachable next step, a recent gap, and pay-down when debt costs more | Upward comparison can discourage, and fixed saving teaches a wrong lesson | A/B, plus my inference | 3.8 |
| 14 | **Show neighbours on boards instead of the top 10,** with the player's best board first and approval for stable players | A newcomer's first look should offer a reachable rank | B | 4.2, 4.3, 4.4 |
| 15 | **Direct one short set piece, the first close, with hard cuts:** bell, coin and paper sounds, baked for web, plus the next story clue | The first moment that feels authored. Also where Portal found its dry point | C | 5.2, 5.4, 5.6, 5.7 |

**Decisions needed from the founder**
- Change 2 touches the rules and the "month is 20 minutes" plan number.
- Change 6 relaxes the standing minimal-motion rule.
- Changes 13 and 14 alter wording in the spec (the 10% ghost and top-10 boards).
- The opening resembles Stardew's. Keep it knowingly, or change the relative.
