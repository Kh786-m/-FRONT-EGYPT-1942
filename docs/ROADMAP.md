# Roadmap / status

## Done in branch `integrate-zips-and-pro-groundwork`
- Good files from all 3 zips integrated into a clean repo layout (bad-CRC `index.html` from the Cloud APK zip skipped).
- Prototype refactored into a reusable mission controller; all prototype features kept.
- Patrol AI (waypoints, view cone + line of sight, return fire, search), damage + regen, fail / complete screens, pause.
- Campaign system (4 chapters, 7 missions defined, 2 playable), progress save, stars, XP/coins.
- New map: Alexandria Harbour (dusk) with water shader, tram, warehouses, cranes, feluccas, fort, market, lamps.
- Procedural animated 3D soldier bodies (hero/ally/enemy) + 3D menu diorama.
- Graphics: procedural skies, fog, glow, filmic tonemap, MSAA, bigger shadow maps, quality toggle (HIGH/LOW).
- Arabic font bundled; Arabic signs/labels render shaped correctly.
- Bug fixed: original map could spawn ruins on top of targets (mission unwinnable).
- CI: headless smoke test of both missions before APK export.

## Still missing for a "full professional" release
- Authored 3D art: rigged/animated hero & soldiers (.glb), modular building kits, PBR textures, FP arms.
- Audio: weapons, ambience, music, Egyptian Arabic voice acting.
- Missions 3–7 maps + scripting (stealth, escort, train defence, minefield, finale), cutscenes.
- Civilians / NPC crowds, navmesh-based AI (cover use, flanking), grenades, more weapons.
- Settings menu (sensitivity, FOV, language), controller support, accessibility, localisation files.
- Release signing keystore, Play Store listing, performance profiling on real phones.
