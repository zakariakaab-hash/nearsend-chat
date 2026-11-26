# Nearsend Chat: product strategy, UX audit and growth plan

26 November 2026. Based on the iOS code (`NearsendChatiOS/`, about 5,500 lines of Swift), screenshots of the current build in
the simulator (demo data), the Android inventory (`INVENTORY.md`), the audit from today (`AUDIT_2026-11-26.md`) and web research.

**How to read this:** facts about the app come from the code. Market facts come from cited sources. Everything marked
*idea* or *hypothesis* is brainstorming, not validated demand. Nothing has been tested between real phones by me; build 9
(uploaded today) is the first build with photo and voice delivery fixed for real Bluetooth.

---

## 1. The app today

### 1.1 What it is

A SwiftUI app with four tabs (Nearby, Chats, SOS, You). Phones talk over Bluetooth LE: each phone is both a central and a
peripheral, packets are flooded up to 5 hops, and private messages are sealed end to end (X25519, HKDF, ChaCha20-Poly1305,
CryptoKit). No server, no account, no phone number, no analytics.

### 1.2 Feature status

| Status | Features |
|---|---|
| **Implemented** (works in the simulator; texts confirmed on real phones by you) | Private chats with Sent / Delivered / Read ring; group chats (one sealed copy per member); public Nearby channel; announcements that expire; SOS with optional position and local emergency number; contacts by QR or pasted code; fingerprint verification; emoji/colour or photo avatar; 12 languages incl. Arabic RTL; battery saver (black screen, dimming); hide previews; auto-delete; relay on/off; Erase everything; demo mode; onboarding (4 pages) |
| **Implemented, not yet verified on devices** | Photos (about 14 KB) and voice notes (12 kbit/s) over Bluetooth: broken until build 9; 20 s connection timeout; key pinning against impersonation; background Bluetooth with state restoration |
| **Partial** | Store-and-forward: the router keeps packets for others, but nothing proves it across app restarts or long gaps; groups: no admin, no removal, no key change when someone leaves; location: only inside SOS and as a one-off location bubble |
| **Planned / in docs only** | Internet relay (Android has an optional Nostr switch, iOS has none); Wi-Fi peer-to-peer; event rooms by QR; password-protected or open groups (deferred) |
| **Missing** | Live location among friends; message search; any way to join a group by QR; sync between your own devices; Android parity for voice notes, contact cards and fragmented writes |
| **Broken / misleading** | The radar places people at **made-up directions**: the angle is a hash of their id (`NearbyView.angle`), and rings suggest distance. Bluetooth gives neither. See 6.1 |

### 1.3 Hard limits you have to design around (iOS)

- **Range:** Bluetooth LE between two phones is typically tens of metres, less through bodies, walls and steel. Every
  extra phone helps; in an empty field two friends 300 m apart will not connect.
- **Background:** iOS keeps Bluetooth working in the background, but scanning gets slower and advertising changes
  form. **If the user force-quits the app, nothing works** until it is opened again. This must be explained, not hidden.
- **Bandwidth:** a few KB/s in practice. Photos must stay tiny; video is out over Bluetooth.
- **Wi-Fi Aware (iOS 26, iPhone 12 and later)** now lets apps make direct Wi-Fi links without a router. It could carry
  real photos and files between paired phones, and talks to Android ([Apple docs](https://developer.apple.com/documentation/wifiaware),
  [MacRumors](https://www.macrumors.com/2025/06/21/ios-26-adding-two-new-wi-fi-features/)). It needs pairing and is new,
  with reported interop bugs ([Apple forums](https://developer.apple.com/forums/thread/790195?page=2)). Advanced phase.
- **GPS works without internet.** Phones get a position from satellites with no data connection. This is the most
  under-used fact in the whole category and the basis of the top feature below.

---

## 2. Market and competitors

### 2.1 What the market shows

- **Demand comes in spikes.** Bitchat jumped to the top of the App Store charts during the Nepal social-media ban, in
  Madagascar, in France during an outage and riots, in Jamaica after Hurricane Melissa, in Uganda before an election and
  in Iran during the 2026 blackout ([Decrypt](https://decrypt.co/339015/jack-dorseys-bitchat-surges-in-nepal-indonesia-amid-protest-crackdowns),
  [Gizmodo](https://gizmodo.com/jack-dorseys-bitchat-becomes-frances-top-social-app-amid-riots-and-mobile-network-outage-2000829670),
  [Decrypt](https://decrypt.co/346748/bitchat-tops-jamaica-app-charts-hurricane-melissa-cuts-connectivity?amp=1),
  [The National](https://www.thenationalnews.com/future/2026/03/19/iran-internet-status-bitchat-alternative/)).
  Bridgefy had the same pattern in Hong Kong and Myanmar ([Rappler](https://www.rappler.com/technology/apps/bridgefy-downloads-after-myanmar-coup/)).
- **Retention is the known weakness.** A mesh app is only useful when people nearby have it, so it gets installed in a
  crisis and deleted after ([Sacra](https://sacra.com/chat/h/a826744b-f8fe-4259-99bf-b971ff17dff4/)).
- **Security claims get tested hard.** Bridgefy was broken twice by academics ([Royal Holloway](https://royalholloway.ac.uk/about-us/news/royal-holloway-cryptographers-urge-caution-over-use-of-secure-messaging-app),
  [USENIX 2022](https://www.usenix.org/conference/usenixsecurity22/presentation/albrecht)); Bitchat launched with an
  impersonation flaw ([TechCrunch](https://techcrunch.com/2025/07/09/jack-dorsey-says-his-secure-new-bitchat-app-has-not-been-tested-for-security),
  [Trail of Bits](https://blog.trailofbits.com/2025/07/18/building-secure-messaging-is-hard-a-nuanced-take-on-the-bitchat-security-debate/)).
  Nearsend had the same class of flaw until today.
- **Festival friend-finding is a real, unsolved itch.** Official festival apps offer location sharing that needs signal;
  small apps like FestivAir try Bluetooth squad tracking; the common advice is still "agree a meeting point"
  ([Express & Star](https://www.expressandstar.com/uk-news/new-glastonbury-app-helps-friends-find-each-other-and-their-tent-more-easily-5799745),
  [eFestivals forum](https://www.efestivals.co.uk/forums/topic/232515-how-to-find-your-tent-and-friends/)).

### 2.2 Competitors

| App | Loved for | Hated for / weakness | Lesson for Nearsend |
|---|---|---|---|
| WhatsApp / Telegram | Everyone is there; groups; media | Need internet; phone number; Meta / data concerns | Don't compete as a daily messenger. Be the app for when they stop working |
| Signal | Trusted crypto, audits | Needs internet and a phone number | Trust is earned by audits; don't claim Signal-level security |
| Briar | Serious security, Tor, contacts only | Android only, slow, hard UX; no iOS app ([Briar FAQ via Kaspersky](https://www.kaspersky.com/blog/mesh-messengers/54192/)) | The iOS gap for a *simple, friendly* offline app is real |
| Bridgefy | First mover, SDK | Broken crypto twice; ads | Never market to protesters on unaudited crypto |
| Bitchat | Brand (Jack Dorsey), open source, viral in outages, geohash channels | IRC-style public chat with strangers; unaudited; little for small groups | Its centre of gravity is *strangers in a crisis*. Leave that; own *your people, anytime there's no signal* |
| SimpleX / Session | No identifiers at all | Need internet; niche UX | Privacy alone is not a reason to download |
| FestivAir, When.fm | Festival-specific | Single use, small | Proof of the itch; none combine chat, find-a-friend and SOS well |
| Meshtastic | Kilometre range with LoRa radios | Needs hardware, nerdy | Not your fight; possible far-future bridge |

### 2.3 Where to compete, where not

- **Compete:** small groups of people who *already know each other* and go somewhere with bad signal: festivals,
  hiking, ski slopes, camping, cruises, travel without roaming, big venues. The app is useful **with just two
  people**, so it needs no critical mass.
- **Second:** emergency fallback. "Keep it installed for the day the network goes down." This gives a reason to keep the
  app, but not a reason to open it daily.
- **Avoid:** general messaging, stranger social discovery, dating, and anything marketed for protest or high-risk safety
  until an independent audit exists.

---

## 3. Identity

### 3.1 Directions compared

| Direction | Verdict |
|---|---|
| A Internet-free messaging | True but generic; Bitchat owns the headline |
| B Nearby communication | Good mechanism, weak promise on its own |
| C Emergency | Strong reason to keep the app, low daily use, high liability |
| D Private | Necessary, not sufficient |
| E Social with strangers | Moderation burden, App Store UGC rules, safety risk. Avoid |
| F Travel | Strong, overlaps with G |
| G Events and crowds | Strongest moment of need; crowds help the mesh |
| H Digital freedom | Attracts press in crises; risky to promise |

### 3.2 Recommendation: **"Your crew, when there's no signal"** (F + G, with C as the safety net)

- **Audience:** friends and families of 2 to 10 people, aged roughly 18 to 45, who go to festivals, hike, ski, camp,
  cruise or travel without data. Secondary: households preparing for outages.
- **Core problem:** "We split up and can't reach or find each other because there is no signal."
- **Promise:** message your people and find them, with no signal, no account and no phone number.
- **Main advantage:** works at n = 2; GPS-based finding without internet; simple, warm design; privacy by default.
- **Tagline options:** "No signal. Still together." · "Lost signal, not each other." · "Find your people. No signal needed."
- **Why download:** before a trip, one friend says "install this, we're doing Glastonbury / the Alps".
- **Why keep it:** the next trip, plus the SOS and "when the network fails" use.

---

## 4. Fifty feature ideas

All ideas, not validated. Columns: **Diff**iculty (L/M/H), **Bat**tery impact, **Viral** potential (L/M/H),
**Prio**rity (P1 = next, P2 = soon, P3 = later, X = avoid). The description says what it does, the problem it solves and
the benefit.

### Core messaging
| # | Feature | What it does / problem / benefit | Unique | Diff | Bat | Privacy | Viral | Prio |
|---|---|---|---|---|---|---|---|---|
| 1 | Honest delivery states | "Waiting for Maja to be in range", "Carried by 2 phones", "Delivered": no more "did it send?" | Med | L | — | none | L | P1 |
| 2 | Quick replies for crowds | One-tap "On my way", "At the meeting point", "Phone at 10%": typing is hard in a crowd | Low | L | — | none | L | P2 |
| 3 | Message expiry per crew | Crew messages vanish when the trip ends | Med | L | — | positive | L | P2 |
| 4 | Pinned crew note | One sticky note: "Camp is at Purple 14, meet at 23:00 by the big tree" | Med | L | — | none | M | P1 |
| 5 | Priority lane | Short texts and check-ins jump ahead of photos in the queue | Med | M | — | none | L | P2 |

### Bluetooth and mesh
| # | Feature | What it does / problem / benefit | Unique | Diff | Bat | Privacy | Viral | Prio |
|---|---|---|---|---|---|---|---|---|
| 6 | Hot/cold finder | Signal strength from one friend as "warmer / colder" with haptics, for the last 20 m | High | L | M (only while open) | crew only | H | P1 |
| 7 | Reach check | "Can I reach Maja right now?" one tap, with honest answer | Med | L | L | none | L | P2 |
| 8 | Relay credits | Show "Your phone passed on 120 messages today" | Med | L | — | aggregate only | M | P2 |
| 9 | Wi-Fi Aware for photos | Real-size photos between paired friends | Med | H | M | pairing | M | P3 |
| 10 | Smart scan duty cycle | Scan harder when a crew member is missing, softer otherwise | Med | M | saves | none | L | P2 |
| 11 | Persistent store-and-forward | Survive app restarts for 24 h | Low | M | L | encrypted at rest | L | P1 |
| 12 | Mesh health meter | "4 phones around you, messages can travel ~3 hops" | Med | L | — | counts only | M | P2 |

### Offline communication
| # | Feature | What it does / problem / benefit | Unique | Diff | Bat | Privacy | Viral | Prio |
|---|---|---|---|---|---|---|---|---|
| 13 | **Find my crew (GPS + compass, offline)** | Crew members share GPS over the mesh; you see an arrow and metres to each friend. Works without data | **High** | M | M (GPS) | crew-only, time-limited, visible indicator | **H** | **P1** |
| 14 | Meet point | Drop a pin; everyone gets an arrow to it, even out of range later | High | L | L | crew only | H | P1 |
| 15 | "Last seen here" | When a friend drops out of range, keep their last position and time | High | L | — | crew only | M | P1 |
| 16 | Offline breadcrumbs | Arrow back to your tent or car | Med | L | L | on device | M | P2 |
| 17 | Prepare for no signal | Checklist before a trip: crew joined, notifications on, don't force-quit, battery | High | L | — | none | M | P1 |
| 18 | Offline map tiles | Download a map area | Low | H | — | none | M | X (cost, size; arrow is enough) |

### Privacy and security
| # | Feature | What it does / problem / benefit | Unique | Diff | Bat | Privacy | Viral | Prio |
|---|---|---|---|---|---|---|---|---|
| 19 | Location expiry | Location sharing ends with the trip or after N hours, always visible | Med | L | — | core | L | P1 |
| 20 | Trip identity | Use a separate name and key for one event | Med | M | — | positive | L | P3 |
| 21 | Sealed receipts | Receipts can't be faked by relays | Low | M | — | positive | L | P2 |
| 22 | Forward secrecy | Session keys that rotate | Low | H | — | positive | L | P3 |
| 23 | Rotating Bluetooth id | Make tracking a phone by its advert harder | Low | M | — | positive | L | P2 |
| 24 | Independent audit | Paid review of the crypto | Low | — (money) | — | trust | M | P3 |
| 25 | Panic wipe | Erase on a gesture | Low | L | — | positive | L | X (protest framing) |

### Social and discovery
| # | Feature | What it does / problem / benefit | Unique | Diff | Bat | Privacy | Viral | Prio |
|---|---|---|---|---|---|---|---|---|
| 26 | Wave | Send a "👋 I'm here" to a nearby contact without opening a chat | Med | L | — | none | M | P2 |
| 27 | Event channel | Public channel scoped to an event name, auto-expires | Med | M | — | public, labelled | M | P3 |
| 28 | Stranger discovery / profiles | Browse people nearby | Low | M | — | **risky** | M | X |
| 29 | Lost & found board | Public posts "found blue jacket at stage B" | Med | L | — | public | M | P3 |

### Emergency
| # | Feature | What it does / problem / benefit | Unique | Diff | Bat | Privacy | Viral | Prio |
|---|---|---|---|---|---|---|---|---|
| 30 | **Crew check-in "I'm OK"** | One tap answers "everyone OK?"; shows who hasn't replied | High | L | — | crew only | M | P1 |
| 31 | SOS to crew first | SOS goes to your crew with position, optional public | Med | L | — | better than public | M | P1 |
| 32 | Medical card | Allergies, blood type, contact; only sent with SOS | Med | L | — | opt-in | L | P2 |
| 33 | Outage mode | One switch: max relay, low brightness, check-ins every 30 min | Med | M | saves | none | M | P2 |
| 34 | Emergency info offline | Local numbers (done) plus basic first-aid cards | Low | L | — | none | L | P3 |

### Groups and communities
| # | Feature | What it does / problem / benefit | Unique | Diff | Bat | Privacy | Viral | Prio |
|---|---|---|---|---|---|---|---|---|
| 35 | **Crews by QR** | Make a crew, others join by scanning one QR (or a code) | Med | M | — | keys exchanged in person | **H** | **P1** |
| 36 | Crew roles | "Organiser" can rename, set meet point, end trip | Low | M | — | none | L | P2 |
| 37 | Remove member + rekey | Fix "no key change on leaving" | Low | M | — | positive | L | P2 |
| 38 | Crew roster status | Each member: in range, via relay, last seen 12 min ago, battery 40% | High | L | — | crew only | M | P1 |

### Travel and events
| # | Feature | What it does / problem / benefit | Unique | Diff | Bat | Privacy | Viral | Prio |
|---|---|---|---|---|---|---|---|---|
| 39 | Trip mode | A crew with dates; starts and ends sharing automatically | High | M | — | positive | H | P2 |
| 40 | Schedule share | "Seeing Band X at 21:00, Main stage", visible to crew | Med | L | — | crew only | M | P3 |
| 41 | Ski / hike pace | Shows who is behind on the trail by position | Med | M | M | crew only | M | P3 |
| 42 | Cruise mode | Explain range on ships, offline-ready | Low | L | — | none | M | P3 |

### UX and personalisation
| # | Feature | What it does / problem / benefit | Unique | Diff | Bat | Privacy | Viral | Prio |
|---|---|---|---|---|---|---|---|---|
| 43 | Network status bar | One line: "Mesh on · 2 friends in range · 5 phones nearby" | Med | L | — | none | L | P1 |
| 44 | Battery forecast | "At this rate, Nearsend uses ~4% per hour" | High | M | — | none | M | P2 |
| 45 | Live Activity | Crew status and meet-point arrow on the Lock Screen | High | M | L | crew only | M | P2 |
| 46 | Widgets / Control Center | Check-in and SOS from the Lock Screen | Med | M | — | none | L | P3 |

### Viral growth
| # | Feature | What it does / problem / benefit | Unique | Diff | Bat | Privacy | Viral | Prio |
|---|---|---|---|---|---|---|---|---|
| 47 | Crew invite link | Link that installs the app and joins the crew in one step (App Store + code) | Med | M | — | code only | **H** | P1 |
| 48 | Airplane-mode demo | Built-in "try it: switch on Airplane Mode and message your friend" | High | L | — | none | H | P1 |
| 49 | Trip recap card | After the trip: "3 days, 412 messages, 0 bars of signal". Shareable image, no locations | High | L | — | aggregate only | H | P2 |
| 50 | Leaderboards / streaks | Gamified relays | Low | L | — | — | M | X (gimmick) |

---

## 5. The ten that could make it stand out

| Rank | Feature | Why users would love it | Competitive advantage | Difficulty | Viral |
|---|---|---|---|---|---|
| 1 | Find my crew (GPS + compass, #13) | "Where are you?" answered with an arrow and metres, no signal | Nobody in the category does GPS-over-mesh well; it's honest (real metres, not fake Bluetooth distance) | Medium | High |
| 2 | Crews by QR (#35) | One scan and the whole group is set up | Built for real groups, not public chat | Medium | High |
| 3 | Meet point (#14) | Ends the "meet at the usual place" chaos | Works after you lose each other | Low | High |
| 4 | Crew check-in "I'm OK" (#30) | Peace of mind in one tap | Safety without public SOS | Low | Medium |
| 5 | Crew roster status (#38) | See everyone's state at a glance | Turns mesh complexity into one list | Low | Medium |
| 6 | Hot/cold finder (#6) | Fun, useful for the last metres in a crowd | Bluetooth used honestly | Low | High (great on video) |
| 7 | Prepare for no signal (#17) | Fewer failures caused by force-quit and permissions | Fixes the #1 cause of "it doesn't work" | Low | Medium |
| 8 | Crew invite link (#47) | Join before the trip, while there's still signal | Growth loop built into the use case | Medium | High |
| 9 | Honest delivery states (#1) + status bar (#43) | Trust that it's working | Most mesh apps hide this | Low | Low |
| 10 | Live Activity (#45) | Crew and arrow on the Lock Screen | Native iOS polish others lack | Medium | Medium |

Honest notes: Wi-Fi Aware, forward secrecy and an audit are valuable but not what makes people download. Offline maps
are expensive and the compass arrow does the job.

---

## 6. UI/UX audit (current build, simulator, demo data)

### 6.1 Must fix
1. **The radar implies direction and distance it doesn't know.** People are placed at a hash-based angle
   (`NearbyView.swift:250`) on distance rings. Users will walk "north-east" to find Maja. Replace with a view that shows
   only what's true: me → direct links → relayed people, with closeness from signal strength ("very close / close / far"),
   or show real direction only when GPS is shared (feature #13).
2. **dBm in the list** ("Direct · -46 dBm") is engineering talk. Show "Very close", "Nearby", "Far", "Via 2 phones".
3. **"5 people in range · 3 reachable via relay"** reads as 8 people. Say "2 nearby · 3 more through other phones".
4. **The default name is "anon-1234"** (in the simulator it showed "115"). The name page now exists in onboarding; make
   sure it's never skipped silently.
5. **SOS content hides under the tab bar** ("Alarms nearby" is cut off). Add bottom inset / safe-area padding.

### 6.2 Should fix
- **Hierarchy:** every screen is light-blue cards on a blue gradient with the same weight. The main thing on each screen
  (status on Nearby, the SOS button) should stand out; secondary cards should recede.
- **Mesh toggle on the Nearby card has no label.** A bare switch next to "5 people in range" doesn't say what it turns
  off. Label it "Nearsend on".
- **The You tab mixes identity and settings.** Split into "You" (name, picture, code) and "Settings" (privacy, language,
  battery, erase).
- **Condensed all-caps titles** (NEARBY, CHATS) are distinctive. Keep them, but check they scale with Dynamic Type and
  read well in Arabic and Japanese, where caps don't exist.
- **Status ring in chats** ("Delivered") is good. Add the waiting reason ("Maja is out of range").
- **SOS as a permanent red tab** is alarming for everyday use. Keep it, but in the crew world "Check-in" plus SOS could
  live in one "Safety" tab.

### 6.3 Nice to have
- Haptics on delivery and on hot/cold.
- Adopt system Liquid Glass for the floating round buttons (they already look like it) rather than custom blur.
- Empty states that teach: "No one nearby yet. Ask a friend to open Nearsend, or try the Airplane-mode demo."

### 6.4 Works well
Native tab bar, WhatsApp-style bottom confirmation sheets, readable bubbles, clear encryption label, clear SOS
disclaimer, local emergency numbers, 12 languages, large-text support, emoji avatars.

---

## 7. UX redesign plan

1. **Home:** make **Crews** the first tab. Each crew card shows members with status dots and the meet point. If you
   have no crew: two big buttons, "Start a crew" and "Join with QR". Nearby people and the public channel move into a
   second tab ("Around me").
2. **Bluetooth/network status:** one status line at the top of Crews and Around me:
   *"On · 2 of 4 friends in range · 6 phones nearby"* → tap for details. States: Off (with fix button) · Looking ·
   Connected · Only via relay · Paused. Never more than one line unless something is wrong.
3. **Discovery:** list, not radar. Each person: avatar, name, "Very close / Nearby / Far / Via 2 phones", last seen.
   Optional "Find" button opens the arrow (GPS) or hot/cold (Bluetooth) view.
4. **Messaging:** keep bubbles; add waiting reason, quick replies, pinned crew note, and the photo progress that exists.
5. **Onboarding (3 screens, under 20 seconds):** (1) "No signal. Still together." with the animated relay; (2) Bluetooth
   permission with the reason and the force-quit warning; (3) your name, then "Start a crew / Join a crew".
6. **Network view:** a small diagram on the crew screen: you in the centre, friends connected directly, friends reached
   through others, with a line count instead of geography. It answers "will my message get there?", which is useful,
   not decorative.

---

## 8. Design concepts

| | 1 Minimal Premium | 2 Futuristic Network | 3 Social & Friendly |
|---|---|---|---|
| Palette | White / near-black, one accent (deep blue #2457D6), grey surfaces | Black, electric cyan #2FE6FF, signal green, glowing lines | Sky blue gradient (current), warm sand, coral for alerts, emoji colours |
| Type | SF Pro, large titles, lots of space | SF Mono for data, condensed headings | Current condensed display titles + SF Pro Rounded body |
| Icons | SF Symbols, thin | Custom line icons, nodes | SF Symbols filled, emoji avatars |
| Navigation | 3 tabs, standard | Network map as home | Crews / Around me / Safety / You |
| Home | Chats list | Live node graph | Crew cards with faces and meet point |
| Discovery | Simple list | Radar and node graph | Faces with "very close / far" chips |
| Messaging | Plain bubbles | Bubbles with route lines | Friendly bubbles, quick-reply chips |
| Animation | Subtle | Pulses, particles | Playful waves, haptics |
| Strength | Feels trustworthy, ages well | Memorable, screenshot-friendly | Mass appeal, matches festival/travel use, closest to today |
| Weakness | Looks like every app | Nerdy, encourages fake geography, battery | Can feel childish if overdone |

**Choice: Concept 3, Social & Friendly, with Concept 1's discipline** (fewer cards, one accent, clear hierarchy). The
audience is friend groups, not engineers; the current app is already close, so it costs weeks, not months; and
Concept 2 pulls straight back to the fake-radar problem.

---

## 9. Growth with almost no budget

### 9.1 The loop
Use case **is** the invite: a trip organiser creates a crew → shares the invite link in the existing WhatsApp group
*before* the trip → friends install and join while they still have signal → at the event it works → someone
films "zero bars, still finding each other" → next trip, a different friend organises. No referral rewards needed.

### 9.2 Organic channels (solo-friendly)
- **Short video (TikTok, Reels, Shorts):** the format is obvious and repeatable: "Airplane mode on. Watch this." Film
  hot/cold finding in a crowd, the arrow at a festival, a ski lift. 3 videos a week for 8 weeks.
- **Reddit:** be useful, don't spam: r/festivals, r/glastonbury, r/burningman, r/Coachella, r/CampingandHiking,
  r/skiing, r/solotravel, r/Cruise, r/preppers, r/privacy. Answer "how do we find each other with no signal" threads.
- **Hacker News "Show HN" and Product Hunt:** open source (GPL), no servers, honest limits. Launch once Crews exists.
- **Outage readiness:** spikes happen when networks fail. Keep a one-page press kit and an "Offline messaging during
  outages" page on nearsend.app ready; post fast when an outage hits the news, without overclaiming.
- **App Store:** keywords below; ask for a rating after a successful delivery to a friend, never during setup.

### 9.3 Real world
- Ask 3 small/medium local festivals to list Nearsend in their "what to bring" email (free for them, useful to fans).
- University freshers' and outdoor clubs: hiking, ski and scout groups; offer a 10-minute demo.
- Leave QR cards at hostels and campsites near areas with bad signal.
- Volunteer crews (stewards, marshals) at events: a real coordination need and a great testimonial.

---

## 10. App Store positioning

Only claim what the shipped build does. Features in *italics* need to be built first.

**Recommended (A, Crew):**
- Name (30): `Nearsend – Chat Without Signal`
- Subtitle (30): `Find your friends, no signal` (28) *(after Find my crew ships; until then `Bluetooth chat with no signal`)*
- Keywords (100): `offline,festival,hiking,camping,mesh,bluetooth,walkie talkie,no internet,group,sos,ski,travel` (93)
- Promotional text: "Going somewhere with no signal? Start a crew before you go and stay in touch over Bluetooth."
- Screenshots: 1 "No signal. Still together." (crew screen, 0 bars) · 2 *"Find your friends"* (arrow) · 3 Private chat,
  encrypted · 4 *Meet point* · 5 SOS to your crew · 6 "No account. No phone number."
- Preview video (15–30 s): Airplane mode switch → message arrives → photo → arrow points to friend in a crowd → wave.
- Category: Social Networking; secondary Travel (better fit than Utilities for the crew use).

**Alternative B, "No-signal messenger":** subtitle `Messages with no internet`. Broadest, most crowded, competes head-on
with Bitchat.

**Alternative C, "Emergency fallback":** subtitle `Stay in touch when networks fail`. Strong in outages, weak daily,
higher scrutiny from App Review.

**Never claim:** unlimited range, guaranteed delivery, "works anywhere", "secure for activists", "decentralised internet".
Always state: needs the app on the other phone, range is limited, don't force-quit.

---

## 11. Roadmap

### Phase 1: fix and polish (weeks 1–3)
| Task | Value | Prio | Effort | Complexity | Depends on | Risk |
|---|---|---|---|---|---|---|
| Device test of build 9 (checklist in the audit) | Confirms photos/voice | P0 | 1 day | L | 2–3 iPhones | Finds new bugs |
| Replace fake radar with honest list/network view | Trust | P0 | 3 days | L | — | Loses the "wow" radar |
| Human signal labels, status line, Nearby wording | Clarity | P1 | 2 days | L | — | — |
| Persist store-and-forward across restarts | Reliability | P1 | 3 days | M | — | Storage, encryption at rest |
| Android: fragmented writes, voice, contact cards | Cross-platform | P1 | 1–2 weeks | M | — | Android BLE quirks |
| Don't-force-quit guidance | Fewer failures | P1 | 1 day | L | — | — |

### Phase 2: standout features (weeks 4–9)
| Task | Value | Prio | Effort | Complexity | Depends on | Risk |
|---|---|---|---|---|---|---|
| Crews by QR + invite code | Core of the product | P1 | 2 weeks | M | groups code | Group key changes |
| Find my crew (GPS + compass) | The headline | P1 | 2 weeks | M | Crews | Battery, location permission review |
| Meet point + last seen | Daily usefulness | P1 | 4 days | L | GPS sharing | — |
| Check-in "I'm OK" + SOS to crew | Safety | P1 | 4 days | L | Crews | — |
| Hot/cold finder | Fun, viral | P2 | 3 days | L | — | Noisy RSSI |
| Crew roster status | Clarity | P1 | 3 days | L | Crews | — |

### Phase 3: growth (weeks 8–13, overlaps)
| Task | Value | Prio | Effort | Complexity | Depends on | Risk |
|---|---|---|---|---|---|---|
| Invite link (App Store + crew code) | Growth loop | P1 | 4 days | M | Crews; nearsend.app page | Universal links setup |
| New store listing, screenshots, video | Conversion | P1 | 1 week | L | Phase 2 | — |
| Content: 3 short videos / week | Reach | P1 | ongoing | L | real phones, friends | Time |
| Show HN / Product Hunt | Spike, feedback | P2 | 2 days | L | stable build | Harsh security comments |
| Festival / club outreach | Real users | P2 | ongoing | L | — | Seasonality (summer) |

### Phase 4: advanced (after 3 months)
Live Activity; Wi-Fi Aware photos; trip mode; sealed receipts; rotating Bluetooth ids; forward secrecy; independent
audit (only with money or a grant, e.g. NLnet / OTF-style funds).

---

## 12. Decision matrix

Scores 1–10: User value, Uniqueness, Market demand, Technical feasibility, Solo feasibility, Viral, Cost efficiency.
Overall = average.

| Idea | UV | Uq | MD | TF | SF | Vir | CE | **Avg** |
|---|---|---|---|---|---|---|---|---|
| Meet point | 9 | 8 | 8 | 9 | 9 | 8 | 10 | **8.7** |
| Find my crew (GPS) | 10 | 9 | 8 | 7 | 7 | 9 | 9 | **8.4** |
| Crews by QR | 9 | 6 | 8 | 8 | 8 | 9 | 10 | **8.3** |
| Check-in "I'm OK" | 8 | 8 | 7 | 9 | 9 | 6 | 10 | **8.1** |
| Hot/cold finder | 7 | 8 | 6 | 8 | 9 | 8 | 10 | **8.0** |
| Honest status line + labels | 8 | 6 | 7 | 10 | 10 | 4 | 10 | **7.9** |
| Crew roster status | 8 | 7 | 7 | 9 | 9 | 5 | 10 | **7.9** |
| Prepare for no signal | 7 | 7 | 6 | 10 | 10 | 5 | 10 | **7.9** |
| Trip recap card | 5 | 8 | 5 | 9 | 9 | 8 | 10 | **7.7** |
| Invite link | 7 | 5 | 7 | 8 | 8 | 9 | 9 | **7.6** |
| Live Activity | 7 | 7 | 6 | 7 | 7 | 6 | 10 | **7.1** |
| Persistent store-and-forward | 7 | 3 | 6 | 7 | 7 | 2 | 10 | **6.0** |
| Wi-Fi Aware photos | 6 | 6 | 5 | 4 | 4 | 5 | 9 | **5.6** |
| Forward secrecy | 5 | 3 | 4 | 4 | 4 | 2 | 9 | **4.4** |
| Offline maps | 7 | 3 | 7 | 4 | 3 | 5 | 3 | **4.6** |
| Stranger discovery | 4 | 3 | 5 | 7 | 6 | 7 | 8 | **5.7** (but X for safety) |

The simple features win because they solve the moment of need ("where are you?") with code you already have (groups,
location bubble, SOS location, QR contacts). Meet point scores highest because it's tiny, works even after people lose
range, and explains the app in one screenshot.

---

## 13. Final strategy

1. **What it should become:** the app friend groups install *before* going somewhere with no signal, to message and
   find each other there. Emergency fallback is the reason it stays installed.
2. **Strongest USP:** find your friends and message them with zero bars, no account, works with just two phones.
3. **Ideal audience:** friend groups and families going to festivals, mountains, campsites, cruises and abroad;
   18–45; one "organiser" per group.
4. **Biggest weaknesses today:** nothing proven on real phones yet; fake radar geography; technical language (dBm, relays);
   one-to-one and public chat but no real *group-of-friends* flow; Android behind; useless if the app is force-quit.
5. **Top design improvements:** honest discovery view; one-line network status; Crews as home; separate Settings from
   You; fewer equal-weight cards.
6. **Top 10 features:** section 5.
7. **First three:** Crews by QR → Meet point → Find my crew (GPS + compass). Each builds on the one before; each is
   shippable alone.
8. **Avoid:** stranger discovery and dating, offline maps, tokens/crypto, internet relays, protest marketing, gamified
   streaks, anything claiming range or security you can't prove.
9. **Attractive to new users:** the airplane-mode demo, a 3-screen onboarding, and a home screen that shows faces of
   friends, not a radar of strangers.
10. **Invites:** the invite *is* the setup: "join our crew for Saturday".
11. **Traction for ~€0:** short videos, Reddit help threads, 3 festival "what to bring" mentions, Show HN, outage press
    kit. Measure: crews created, crews with 3+ members, 7-day retention per crew.
12. **30 days:**
    - Week 1: device test build 9; fix what breaks; honest radar/list; signal labels; status line.
    - Week 2: Crews by QR (create, join, roster).
    - Week 3: Meet point + last seen + check-in.
    - Week 4: TestFlight with 3 real friend groups at any outdoor outing; collect logs; fix.
13. **90 days:**
    - Month 2: Find my crew (GPS + compass), hot/cold finder, invite link, new App Store listing, first 10 videos.
    - Month 3: public launch (Show HN, Product Hunt), festival/club outreach for the summer season, Android parity,
      Live Activity; decide on Wi-Fi Aware based on user requests for bigger photos.

### Sources
[Decrypt (Nepal)](https://decrypt.co/339015/jack-dorseys-bitchat-surges-in-nepal-indonesia-amid-protest-crackdowns) ·
[Gizmodo (France)](https://gizmodo.com/jack-dorseys-bitchat-becomes-frances-top-social-app-amid-riots-and-mobile-network-outage-2000829670) ·
[Decrypt (Jamaica)](https://decrypt.co/346748/bitchat-tops-jamaica-app-charts-hurricane-melissa-cuts-connectivity?amp=1) ·
[The National (Iran)](https://www.thenationalnews.com/future/2026/03/19/iran-internet-status-bitchat-alternative/) ·
[Rappler (Bridgefy, Myanmar)](https://www.rappler.com/technology/apps/bridgefy-downloads-after-myanmar-coup/) ·
[Sacra (retention)](https://sacra.com/chat/h/a826744b-f8fe-4259-99bf-b971ff17dff4/) ·
[Royal Holloway](https://royalholloway.ac.uk/about-us/news/royal-holloway-cryptographers-urge-caution-over-use-of-secure-messaging-app) ·
[USENIX 2022](https://www.usenix.org/conference/usenixsecurity22/presentation/albrecht) ·
[TechCrunch](https://techcrunch.com/2025/07/09/jack-dorsey-says-his-secure-new-bitchat-app-has-not-been-tested-for-security) ·
[Trail of Bits](https://blog.trailofbits.com/2025/07/18/building-secure-messaging-is-hard-a-nuanced-take-on-the-bitchat-security-debate/) ·
[Kaspersky (mesh apps)](https://www.kaspersky.com/blog/mesh-messengers/54192/) ·
[Apple Wi-Fi Aware](https://developer.apple.com/documentation/wifiaware) ·
[MacRumors](https://www.macrumors.com/2025/06/21/ios-26-adding-two-new-wi-fi-features/) ·
[Apple forums](https://developer.apple.com/forums/thread/790195?page=2) ·
[bitchat-android releases](https://github.com/permissionlesstech/bitchat-android/releases) ·
[Express & Star (Glastonbury app)](https://www.expressandstar.com/uk-news/new-glastonbury-app-helps-friends-find-each-other-and-their-tent-more-easily-5799745) ·
[eFestivals forum](https://www.efestivals.co.uk/forums/topic/232515-how-to-find-your-tent-and-friends/)
