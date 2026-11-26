# Nearsend Chat: product vision validation and UI direction

26 November 2026. Builds on `PRODUCT_STRATEGY_2026-11-26.md` (market research and sources are there) and the audit
`AUDIT_2026-11-26.md`. Evidence used: the iOS code, simulator screenshots of the current build (demo data), today's fixes,
and the reference screens you shared. **Labels used below:** *Fact* = from code, tests or a cited source. *Hypothesis* =
my judgement, not yet validated with users.

---

## 1. Executive summary

Your vision is right, and I would ship it almost as written. Three corrections:

1. **Crews must work before the trip and still work without any internet.** A join link can only *start* a join. The
   keys are exchanged when the phones first meet over Bluetooth. Design for a "pending" member state instead of
   pretending the link completes the join.
2. **Find my crew is GPS, never Bluetooth.** Bluetooth gives a rough "very close / near / far" and nothing else. Distance
   and the compass arrow must come from GPS positions sent between phones, shown with their **age** and **accuracy**.
3. **The 4-week plan is about 6 weeks of work.** Crews with a safe join flow take more than a week, and Find my crew
   should come after Meet point, not in the same week. Section 11 has the corrected plan.

**Decision:** Nearsend becomes *the crew app for places with no signal*. Home = your crew. First three features: Crews by
QR → Meet point + check-in → Find my crew.

---

## 2. Product identity

| | |
|---|---|
| **Positioning** | Group coordination for friends going where the signal is bad. Not a daily messenger, not a stranger network, not an emergency service. |
| **Audience** | Groups of 2–10 friends or family: festivals, camping, hiking, ski, cruises, road trips, travel without roaming. One "organiser" per group. |
| **Tagline** | No signal. Still together. |
| **USP** | Make a crew in 30 seconds, then message, meet up and find each other with zero bars. No account, no phone number, and it already works with two phones. |
| **Why install** | A friend sends "join our crew for Saturday" before the trip. |
| **Why keep** | The next trip, plus the reassurance of check-ins and SOS when the network fails. |

**Five-second test** *(hypothesis)*: the App Store screenshot "No signal. Still together." over a crew screen showing
"0 bars" and an arrow to a friend explains the app without words.

---

## 3. Market analysis (short; details and sources in the strategy doc)

| | Facts | Hypotheses |
|---|---|---|
| Demand | Offline messengers spike in outages, protests and disasters (Bitchat, Bridgefy). Festival goers already use workarounds (meeting points, What3Words, official apps with online location sharing). | Small groups at events have a recurring need, every season, which crisis use doesn't give. |
| Gap | Bitchat focuses on public chat with strangers; Briar has no iOS app; festival apps need signal or extra hardware (screens you shared: LoRa devices, map apps). | No app combines **crew + meet point + GPS finding + check-in** offline on plain iPhones. |
| Risks | Bluetooth range is limited; iOS stops everything after force-quit; mesh apps lose users after the spike. Crypto in this space gets attacked publicly. | Seasonality (summer festivals); people may forget to install before the trip. |

**Where we win:** small groups, trips, simplicity, honesty about range. **Where we don't fight:** daily messaging,
big public crisis networks, activists.

---

## 4. Revalidating the known UI problems (checked on the simulator today)

| # | Problem | Status now |
|---|---|---|
| 1 | Radar positions made up from device ids | **Fixed today.** People sit on rings by signal strength ("Very close / Near / Far / Through other phones"), spread evenly, with the line "Rings show signal strength, not direction." Verified in the simulator. |
| 2 | Raw "-46 dBm" | **Fixed today.** List shows "Very close", "Near", "Far", "Through 2 other phones". RSSI stays noisy, so these are coarse on purpose. |
| 3 | Direct vs relayed counts | **Fixed today.** "2 people in range · Plus 3 through other phones". The switch is now labelled On / Paused. |
| 4 | SOS hidden under the tab bar | **Partly valid.** It isn't hidden: the page scrolls. But "Alarms nearby" starts under the floating tab bar, so a new alarm can go unseen. Fix: when an alarm is active, show it at the top of the page. |
| 5 | You mixes identity and settings | **Still valid.** One long page: profile, fingerprint, language, privacy, battery, demo, erase. You also dislike the fingerprint card. Five alternatives were shown in chat; recommendation in 6.2. |
| 6 | Home should be crews | **Still valid.** The app opens on Nearby (radar). There is no crew concept yet. |
| 7 | One primary action per screen | **Still valid on Nearby** (switch, radar, list, announcements, post) and **on You**. Chats and SOS are fine. |
| 8 | Friendly, modern, consistent | **Mostly.** Consistent cards and colours, but every card has the same weight, so nothing leads. |

New today: when Bluetooth is off, iOS shows its own alert, whose buttons apps can't change. If the person taps Close,
the app now opens an **animated guide** (Control Center or Settings → Bluetooth, incl. "Allow New Connections"), which
closes itself when Bluetooth comes on.

---

## 5. Screen-by-screen design audit

| Screen | Works | Problems | Fix |
|---|---|---|---|
| **Onboarding (4 pages)** | Animated icons, name page, contextual Bluetooth request | 4 pages before value; ends in an empty app | 3 pages: promise → Bluetooth (+ "don't force-quit") → name, then **Start a crew / Join a crew** |
| **Nearby** | Honest radar now, clear list, help when Bluetooth is off | Too much on one page; announcements buried at the bottom | Becomes "Around me", the second tab; the radar card can shrink to one line + "Show radar" |
| **Chats** | WhatsApp-like list, filters, + menu, unread badges | The public Nearby channel sits among private chats; crews will need their own place | Crews get their own home; Chats keeps 1:1 and public |
| **Thread** | Bubbles, status ring, encryption label, voice, photos | No reason shown while waiting; no quick replies | "Waiting for Maja to be in range"; quick-reply chips in crew chats |
| **SOS** | Clear disclaimer, local number, location permission check | Alarms list below the fold; red tab every day | Active alarms at the top; later merge into a "Safety" area of the crew with check-in |
| **You** | Avatar, no-account promise, fingerprint, privacy switches | Long; settings and identity mixed; fingerprint card heavy; default name "anon-1234" | Split **You** (profile + My code) and **Settings**; make the name required in onboarding |
| **Sheets** (confirm, attach, add contact, My code) | Bottom sheets, clear buttons | Fine | Keep the style |
| **Empty states** | Nearby "No one in range yet" with tips and invite | Chats empty state is plain | Empty home = Create / Join a crew |
| **Accessibility** | Large text, VoiceOver labels, Reduce Motion respected, RTL | Condensed caps titles don't exist in Arabic/Japanese; check large sizes | Keep, test at XXL |
| **Dark mode / saver** | Battery saver = black, flat | Default dark mode not designed separately | Borrow contrast from the dark references, not neon |

---

## 6. Recommended UI direction

### 6.1 Three concepts

| | A. Social & Friendly (current, refined) | B. Outdoor Premium (your hiking reference) | C. Minimal Network (your node-graph reference) |
|---|---|---|---|
| Colours | Sky blue, white glass cards, coral for alerts, emoji avatars | Charcoal #1C1F24, white cards, one signal colour (lime #C8F51E) for "go" actions, photo backgrounds | Near-black, cyan nodes and thin lines |
| Type | Condensed display titles + SF Pro | SF Pro, large numbers ("1.2 km"), small grey labels | SF Pro + SF Mono for figures |
| Components | Rounded glass cards, pills | Big white arrow tile, dark stat rows, pill buttons | Node graph, thin outlines |
| Home | Crew card with faces | Crew header over a trip photo, stats (members in range, meet point km) | Live graph of the crew |
| Crew screen | Member list with status chips | Member rows with distance, age, accuracy | Graph + side list |
| Nearby | Rings by signal strength | Plain list | Graph |
| Chat | Friendly bubbles | Dark bubbles, quick replies | Bubbles with route hints |
| Motion | Soft waves, haptics | Arrow turning with the compass, number counting | Pulses along links |
| Strength | Warm, mass appeal, already built | Feels premium and outdoor-ready; the arrow tile is the best "find" UI in any reference | Explains the mesh |
| Weakness | Can look childish; low hierarchy | Photos cost size; risk of copying a hiking app | Technical, invites fake geography, battery |

**Choice: A as the base, borrowing two pieces from B.** Keep the sky-blue identity people already know. Take from B:
(1) the **big white arrow tile with a large distance number** for Meet point and Find my crew, (2) the **one strong
action colour** for "go" actions instead of many equal blue buttons. Use C only for a small "how messages travel"
diagram in the crew info, never as the home screen. *(Hypothesis: B's dark charcoal could be the dark-mode version of A.)*

### 6.2 You screen and the fingerprint card
Recommendation: **option C from the 5 layouts** (code buttons inside the profile card: "My code" and "Scan"), with the
fingerprint moved into the My code sheet. Optionally add **E** (four safety words) inside that sheet later, as an
easier alternative to the hex groups. Settings move to their own page behind a gear in the top-right corner.

### 6.3 Typography, spacing, components
- One display style for page titles (keep the condensed font), SF Pro for everything else. Big numbers in SF Pro Rounded.
- One card style with two weights: **lead card** (white, 24 pt corners, used once per screen) and **list rows**
  (lighter, 16 pt corners). Fewer cards overall.
- One primary button per screen; secondary buttons as outlined pills.
- Haptics: light tap on send, success on delivered, rising "ticks" when the arrow points the right way.

---

## 7. Home screen concept: Crews first

**With a crew (scroll order):**
1. **Crew header:** crew emoji + name ("Glasto 2027"), trip dates, one status line *"3 of 5 in range · 1 via others · 1 last seen 12 min ago"*.
2. **Member strip:** avatars with a status ring (green = in range, outline = through others, grey = last seen …). Tap = profile with Message / Find.
3. **Meet point tile (from B):** white tile with arrow and "240 m · Main gate", age of the pin, "Set meet point" if none.
4. **Check-in row:** big "I'm OK" pill plus "Ask everyone"; shows who answered.
5. **Crew chat preview:** last 2 messages + quick replies ("On my way", "At the meet point", "Need help").

**Without a crew (empty state):** illustration of two phones with no bars, the line "No signal. Still together.", and
two buttons: **Start a crew** (primary) and **Join with QR**. Below: "Or try it now: switch on Airplane Mode and
message someone nearby."

**Tabs:** Crew · Chats · Around me · You (SOS reachable from Crew and from a long-press on the tab bar). This keeps 4 tabs.

---

## 8. Technical reality of the three core features

### 8.1 Crews by QR *(builds on existing groups and contact QR)*
- The QR holds the crew id, name, emoji and the organiser's public key. Scanning it adds the crew locally as **pending**.
- On first Bluetooth contact (directly or via the mesh) the joiner sends a sealed join request, and the organiser's
  phone replies with the member list and keys. Then every member gets the new member's key.
- **Invite link before the trip:** the iOS share sheet sends `nearsend.app/j/<code>`. It opens the App Store if needed,
  then shows "Join Glasto 2027 · you'll be connected when you meet". Works with no server: the link only carries the code.
- Leave, remove (organiser), expiry date (trip end) are realistic. **Changing keys when someone leaves** is needed for
  privacy and adds about 3 days.
- Time: about **8–10 working days** for a solid version.

### 8.2 Meet point
- *Fact:* GPS works without data. Apple Maps tiles don't, so the main UI is an **arrow + distance**, not a map.
- The pin = coordinates + name + time + accuracy, sent sealed to each crew member (a few hundred bytes).
- The arrow uses the compass heading (CoreLocation) and the bearing to the pin. Show the accuracy ("±8 m") and hide the
  arrow when accuracy is worse than 50 m or the compass needs calibration.
- Time: about **4 days**, including saved points (Tent, Car, Stage).

### 8.3 Find my crew
- Each member chooses to share position with the crew for a set time (1 h / until trip ends). There is always a visible
  indicator and a Stop button.
- Updates: every 30–60 s while the app is open, slower in the background or in battery saver. Each friend shows
  "120 m · 1 min ago · ±10 m". After 5 minutes it becomes "Last seen here 7 min ago".
- **Bluetooth "hot/cold" is only for the last few metres** and is labelled as signal strength, not distance.
- *Constraints:* GPS is poor indoors and in dense crowds; background updates need "Always" location, which App Review
  scrutinises. Start with "While using the app" only.
- Time: about **6–8 days** after Meet point (it reuses the arrow tile).

---

## 9. Feature brainstorm (36 ideas)

**Crew coordination:** 1 Crews by QR · 2 Invite link with pending join · 3 Crew emoji and trip dates · 4 Crew expiry ·
5 Organiser role · 6 Pinned crew note · 7 Crew announcements · 8 Member status strip · 9 "Who's missing?" view
**Check-ins and safety:** 10 "I'm OK" one tap · 11 "Ask everyone" check-in · 12 Quick statuses (On my way / At meet
point / Need help) · 13 SOS to crew first, public optional · 14 Emergency meet point · 15 Low-battery heads-up to crew
(sends "Maja's phone at 10%") · 16 Medical note sent only with SOS
**Location:** 17 Meet point with arrow · 18 Saved points (Tent, Car) · 19 Find my crew (GPS) · 20 Last seen here ·
21 Location age + accuracy everywhere · 22 Bluetooth hot/cold for the last metres · 23 Breadcrumb back to the tent
**Messaging:** 24 Waiting reason on messages · 25 Quick replies · 26 Message expiry per crew · 27 Saved held messages
across restarts · 28 Priority for texts over photos
**Trip and events:** 29 One flexible "trip" (dates + places) instead of separate modes · 30 Trip checklist ("Prepare for
no signal") · 31 Trip recap card to share afterwards (no locations)
**UX:** 32 Live Activity on the Lock Screen (arrow + crew status) · 33 Widgets for check-in · 34 Airplane-mode demo ·
35 Animated Bluetooth guide (done) · 36 Dark "Outdoor" theme

---

## 10. Prioritisation

### 10.1 Top 10 (scored 1–10; Avg = mean of the ten criteria)

Criteria: User value, Uniqueness, Demand, Tech feasibility, Solo feasibility, Dev time (10 = short), Reliability,
Battery (10 = light), Privacy, Viral.

| Rank | Feature | UV | Uq | De | TF | SF | Ti | Re | Ba | Pr | Vi | Avg |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Meet point with arrow | 9 | 8 | 8 | 9 | 9 | 8 | 8 | 9 | 9 | 8 | **8.5** |
| 2 | "I'm OK" check-in | 8 | 8 | 7 | 9 | 9 | 9 | 8 | 10 | 9 | 6 | **8.3** |
| 3 | Crews by QR + invite link | 9 | 6 | 8 | 7 | 7 | 5 | 8 | 10 | 9 | 9 | **7.8** |
| 4 | Member status strip | 8 | 7 | 7 | 9 | 9 | 9 | 7 | 10 | 9 | 4 | **7.9** |
| 5 | Quick statuses / replies | 7 | 5 | 7 | 10 | 10 | 10 | 9 | 10 | 9 | 4 | **8.1** |
| 6 | Find my crew (GPS) | 10 | 9 | 8 | 6 | 6 | 4 | 6 | 5 | 6 | 9 | **6.9** |
| 7 | Last seen here | 8 | 8 | 6 | 9 | 9 | 9 | 8 | 9 | 7 | 5 | **7.8** |
| 8 | Waiting reason on messages | 7 | 6 | 6 | 9 | 9 | 9 | 9 | 10 | 10 | 2 | **7.7** |
| 9 | Saved held messages across restarts | 7 | 3 | 6 | 7 | 7 | 7 | 9 | 10 | 8 | 2 | **6.6** |
| 10 | Live Activity | 7 | 7 | 6 | 7 | 7 | 6 | 7 | 7 | 9 | 6 | **6.9** |

Ranks weigh user value over the plain average: Find my crew scores lower on effort and battery but is the feature people
expect (every reference screen you shared shows friends with distance), so it stays in the top 6.

### 10.2 Build first (3)
1. **Crews by QR** (everything else hangs on it).
2. **Meet point + "I'm OK" check-in** (small, high value).
3. **Find my crew** (the headline, built on the Meet point arrow).

### 10.3 Memorable (3)
1. The **arrow tile** pointing at a friend with "120 m · 1 min ago" at a festival with zero bars.
2. **"Everyone OK?"** with each friend's face turning green.
3. **Invite before the trip:** "Join Glasto 2027", which then works by itself on site.

### 10.4 Avoid (5)
1. Stranger discovery, dating or public profiles.
2. Offline maps (size, licences, cost); the arrow is enough.
3. A separate mode per activity (festival, hiking, cruise…); one flexible trip covers them all.
4. Any internet relay or server, which breaks the promise and adds cost.
5. Marketing to protesters, or claiming "secure" or "emergency" before an independent audit.

---

## 11. Roadmap (challenged and corrected)

Your 4-week plan fits **Week 1 + Crews + Meet point/check-in**, but not Find my crew and real-world testing in the same
month. Realistic version:

| Week | Work | Done when |
|---|---|---|
| 1 | Test build 9 on 2–3 iPhones (audit checklist) · fix what breaks · ✅ honest radar · ✅ proximity labels · ✅ counts · ✅ Bluetooth guide · SOS alarms on top · split You and Settings · fingerprint card per chosen layout | Photo and voice confirmed on devices; build 10 on TestFlight |
| 2–3 | Crews: create, QR, invite link, pending join, member list, crew chat, leave/remove, expiry | Three phones form a crew with no internet |
| 4 | Meet point (arrow, distance, age, accuracy, saved points) + "I'm OK" check-in + quick statuses | A crew meets at a pin outdoors |
| 5 | **TestFlight with 3 real friend groups** (park, a gig, a hike) · logs · fixes | Notes from 3 sessions |
| 6–7 | Find my crew (GPS sharing, last seen, stop sharing) · Crew home screen | Friends found at 50–300 m |

**90 days:**
- **Month 1:** weeks 1–4 above.
- **Month 2:** weeks 5–7, then the App Store listing rewritten around crews, screenshots, preview video, invite-link
  landing page on nearsend.app.
- **Month 3:** public launch (Product Hunt, Show HN, Reddit), first festival/outdoor-club partners, Live Activity,
  Android parity for crews.

---

## 12. Growth: first 100, 1,000, 10,000 users (no ad budget)

| Stage | How | Realistic effort |
|---|---|---|
| **First 100** | Your own friends and 3 test groups; 2–3 local clubs (hiking, climbing, scouts, university outdoor club). Each test group invites the next. | 4–6 weeks, mostly in person |
| **First 1,000** | Short videos (3/week: "zero bars, still found her"); helpful answers in r/festivals, r/CampingandHiking, r/solotravel, r/Cruise; Product Hunt + Show HN; App Store listing around "festival, hiking, no signal". | 2–3 months |
| **First 10,000** | Festival "what to bring" mentions (small/medium festivals first); outdoor clubs and student unions; a press kit ready for the next big outage; the invite loop (one organiser brings 3–8 people). *Hypothesis:* 1 crew = 4 installs on average. | 6–9 months, seasonal (summer) |

**The loop is the product:** an organiser creates a crew → shares "Join our crew for Saturday" in the existing group
chat → everyone installs while they still have signal → it works on site → the recap card and videos bring the next
organiser. No referral rewards needed.

**Measure:** crews created, crews with 3+ members, crews used on 2+ days, check-ins sent. Ignore raw downloads.

---

## 13. Final recommendation

Build Nearsend into **the crew app for places with no signal**. Keep the friendly sky-blue identity, add one strong
action colour and the arrow tile. Make **Crew** the home tab. Ship in this order: (1) device-verified build with today's
fixes, (2) Crews by QR, (3) Meet point + check-in, (4) Find my crew. Test with real friend groups before any launch push.
Say only what's true: limited range, needs the app on both phones, no emergency services, GPS accuracy shown on screen.
