# WAR FRONT: EGYPT 1942 — القصة والحملة | Story & Campaign Bible

> Fiction inspired by real places and dates of the 1942 North African campaign.
> Tone rules: the story is about **protecting people and home**, never about hating a nation.
> No real-world extremist symbols, no atrocities shown, no glorification of any regime.
> Enemy forces are shown as soldiers doing a job ("قوات المحور" / "the Axis patrol"),
> not as caricatures. Civilians are never targets; harming them fails the mission (planned rule).

## Historical frame (kept accurate, then fictionalised)
- Egypt in 1942 was formally neutral but occupied as the main Allied base; the war was fought on Egyptian soil.
- **First Battle of El Alamein**: July 1942 (Ruweisat Ridge, Tel el Eisa).
- **Alam el Halfa**: late Aug – early Sep 1942.
- **Second Battle of El Alamein**: 23 Oct – 11 Nov 1942 (minefields nicknamed "the Devil's Gardens").
- Alexandria lived with air-raid sirens, blackouts and a harbour full of ships; the Ramleh tram, the Corniche and the Qaitbay fort are period landmarks.
- Egyptians served as railway men, drivers, labourers, guides, nurses and police — that is our hero's world.

## Hero — خالد كارم عبداللا (Khaled Karem Abdalla)
- 29, from a fishing family in Anfoushi (Alexandria), works as a **desert guide and railway signal-man** on the El Hammam line.
- Knows the desert tracks from Bedouin friends; speaks Arabic, some English and Italian from the port.
- Motivation: his younger brother **Youssef** volunteers as a driver for a supply convoy and goes missing near Alamein. Khaled goes to bring him home — and ends up protecting the villages, the water road and the city.
- Signature look: tarboosh-red field cap, light keffiyeh-style scarf, khaki work jacket, bolt-action rifle (implemented in `SoldierModel.Kind.HERO`).
- Arc: from "I only want my brother" → "this is everyone's home" → final choice in Chapter 4 to lead civilians out of the line of fire instead of chasing glory.

## Supporting cast
| Name | Role |
|---|---|
| **Youssef Karem** | Khaled's brother, convoy driver (missing → rescued in Ch.3) |
| **Hagga Nefisa** | Owns the coffee shop «قهوة المحروسة» in El Hammam; mission-giver, the village's voice |
| **Salem el-Awlad Ali** | Bedouin guide; teaches night navigation by the stars (Ch.1 M3) |
| **Dr. Mariam Fahmy** | Nurse at an Alexandria hospital; Chapter 2 escort missions |
| **Sgt. Hughes** | Weary Allied sergeant; uneasy ally who learns to trust local knowledge |
| **Luca** | Young captured Axis radio-man; humanises the other side, helps in Ch.3 |
| **"El-Raees" (the Foreman)** | Antagonist: a war profiteer running sabotage and smuggling for whoever pays |

## Campaign structure (4 chapters, 7 missions in v1.0, 12 planned for v1.5)
| # | Chapter / Mission | Map | Date | Core gameplay | Status |
|---|---|---|---|---|---|
| 1 | الفصل الأول: رمال العلمين — **نقطة الحراسة / The Desert Outpost** | `m01_alamein_outpost` | Jul 1942 | Tutorial: move, aim, reload, clear a 12-man patrol around the water road | ✅ playable |
| 2 | **ليلة رويسات / Ruweisat Night** | Ruweisat Ridge (night) | Jul 1942 | Stealth: avoid flares & patrol cones, rescue Salem's caravan | 📝 designed |
| 3 | الفصل الثاني: الإسكندرية تنتظر — **ميناء الإسكندرية / Alexandria Harbour** | `m02_alexandria_harbor` | Sep 1942, dusk | Stop 8 saboteurs in the warehouses before charges go off | ✅ playable (v0.2 layout) |
| 4 | **إظلام الكورنيش / Corniche Blackout** | Corniche (night) | Sep 1942 | Air-raid escort of families to the shelter, searchlights, tram cover | 📝 designed |
| 5 | الفصل الثالث: القطار الأخير — **محطة الحمّام / El Hammam Station** | Railway + village | Oct 1942 | On-rails train defence, then free-roam to find Youssef | 📝 designed |
| 6 | الفصل الرابع: نار أكتوبر — **حدائق الشيطان / The Devil's Gardens** | Minefield belt | 23 Oct 1942 | Mine-detection mini-game, mark a safe lane, protect sappers | 📝 designed |
| 7 | **تل العيس / Tel el Eisa** | Coastal ridge + rail | Nov 1942 | Finale: hold the ridge, then lead civilians out; epilogue in Anfoushi | 📝 designed |

### Mission design template (use for every new mission)
1. **Briefing** (AR + EN, 2–3 lines, who/where/why).
2. **Primary objective** (one sentence, measurable).
3. **Optional objective** (stars): e.g. finish with HP ≥ 85, no civilian alerts, under X minutes.
4. **Set-pieces**: 1 opening moment, 1 mid twist, 1 climax.
5. **Map beats**: spawn → first cover → first contact → flank route → climax arena → exit.
6. **Voice lines** (Egyptian Arabic): e.g. «خد بالك يا خالد!» «الطريق أمان، اتحرك!» «يا ساتر يا رب!».

## Meta progression (implemented foundation)
- `Campaign` autoload: chapters/missions, unlock order, stars (1–3 by remaining HP), XP and coins saved to `user://progress.cfg`.
- Planned: coins buy cosmetic gear (scarves, caps, rifle wraps) — no pay-to-win; daily "village help" tasks.

## Map list (new maps for the pro version)
| Map | Biome | Landmarks | Size target |
|---|---|---|---|
| Alamein Outpost (prototype, kept) | Open desert | Ruins, market lane, water road | 180×180 m |
| **Alexandria Harbour** (new, built) | Coastal city at dusk | Corniche + Ramleh tram, warehouses 1–4, cranes, feluccas, Qaitbay-inspired fort, fish market | 200×100 m playable |
| Ruweisat Ridge | Rocky ridge, night | Ridge spine, wadi, Bedouin camp | 300×300 m |
| Corniche Blackout | City night | Searchlights, shelters, tram depot | 250×120 m |
| El Hammam Railway | Desert rail + village | Station, water tower, signal box | 400×150 m |
| Devil's Gardens | Minefield belt | Wire, mine markers, burned vehicles | 300×300 m |
| Tel el Eisa | Coastal ridge | Railway cut, sea cliffs | 350×250 m |
