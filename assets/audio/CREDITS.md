# HARAQ audio credits

All sound effects in this folder are **original, procedurally generated** by
[`tools/gen_audio.py`](../../tools/gen_audio.py) (numpy noise + oscillators, encoded to Ogg Vorbis with ffmpeg/libvorbis).
No third-party recordings are used.

License: **CC0 1.0 Universal** (public domain dedication) — same as the generator script.

| File | What it is |
|---|---|
| shot_webley / shot_enfield / shot_thompson / shot_mp40 | Player gunshots, one per weapon (crack + body + desert slap-back tail) |
| shot_enemy | Enemy rifle shot (darker, distant variant, played positionally) |
| reload, dry, switch | Magazine out/in + bolt, empty click, weapon draw |
| hit_flesh, hit_sand, hit_metal, hurt | Bullet impacts (soldier / sand / metal ricochet) and player hit thump |
| explosion | Distant artillery shell (El Alamein ambience) |
| zone_burn, zone_alarm | Crackling loop while outside the zone, horn when the zone starts closing |
| step | Footstep on sand (pitch-randomised at runtime) |
| wind_loop, sea_loop | Seamless desert wind and Mediterranean surf loops |
| ui_click, pickup | Menu click, loot pickup clink |

Regenerate: `python3 tools/gen_audio.py` (needs numpy and ffmpeg with libvorbis).
