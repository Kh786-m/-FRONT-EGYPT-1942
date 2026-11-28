# HARAQ audio credits

All sound effects **and music** in this folder are **original, procedurally generated** by
[`tools/gen_audio.py`](../../tools/gen_audio.py) (numpy noise + oscillators, encoded to Ogg Vorbis with ffmpeg/libvorbis).
No third-party recordings are used.

License: **CC0 1.0 Universal** (public domain dedication) — same as the generator script.

| File | What it is |
|---|---|
| shot_webley / shot_enfield / shot_thompson / shot_mp40 | Player gunshots, one per weapon — layered (supersonic crack + muzzle blast + sub thump + action clicks) with a desert reverb (discrete dune/ruin slap-backs + 0.75–1.4 s darkening tail) |
| shot_enemy | Enemy rifle shot (darker, distant variant, played positionally) |
| reload, dry, switch | Magazine out/in + bolt, empty click, weapon draw |
| hit_flesh, hit_sand, hit_metal, hurt | Bullet impacts (soldier / sand / metal ricochet) and player hit thump |
| explosion | Artillery shell (crack + body + falling sub + debris rain, 2.2 s rolling tail) — El Alamein ambience |
| zone_burn, zone_alarm | Crackling loop while outside the zone, horn when the zone starts closing |
| step | Footstep on sand (pitch-randomised at runtime) |
| wind_loop, sea_loop | Seamless desert wind and Mediterranean surf loops |
| ui_click, pickup | Menu click, loot pickup clink |
| music_menu | Menu theme (40 s loop, 72 bpm): Hijaz-mode oud-style plucked melody (Karplus-Strong) over a D drone, bendir frame drum, distant horn call |
| music_battle | In-match loop (34 s, 112 bpm): darbuka *maqsum* + military side-drum ruffs/rolls, low plucked Hijaz ostinato, brass stabs and a rising horn line |

Both music loops are composed note-by-note in code (`menu_theme()` / `battle_theme()` in the generator) and are CC0 as well.
In game they play on their own **Music** bus (separate slider from **SFX**) and duck under nearby gunfire and explosions.

Regenerate: `python3 tools/gen_audio.py` (music only: `--music-only`) (needs numpy and ffmpeg with libvorbis).
