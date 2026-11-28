# Art direction & professional 3D pipeline

## Current state (honest)
All 3D in the repo is **procedural** (built in GDScript from boxes, capsules, cylinders):
`scripts/core/level_kit.gd` (props, palms, carts, crates, dunes, environments) and
`scripts/actors/soldier_model.gd` (animated low-poly hero / ally / enemy bodies).
This keeps the build tiny and CI-friendly, and every call site is an API that can be swapped
for authored assets later without touching mission code.

## Look
- Era palette: sun-bleached sand `#B08F5E`, limestone `#CCBD9E`, khaki `#9E8C66`,
  tarboosh red `#8C2620`, Mediterranean `#1E4C5A` (shared with the HARAQ water shader).
- Lighting presets in `LevelKit.apply_environment`: `desert_noon`, `coast_dusk`, `night_blackout`
  (procedural sky, filmic tonemap, fog, glow on HIGH quality, 4096 shadow map on desktop / 2048 mobile, MSAA 2×).
- Water: `assets/shaders/water.gdshader` (vertex waves + fresnel, GL Compatibility-safe).

## Pro 3D pipeline (next steps)
1. **Hero Khaled**: sculpt/base mesh in Blender (or MetaHuman → Blender for likeness, only with Khaled's consent),
   ~15k tris mobile LOD0 / 4k LOD1, 2k PBR textures (albedo/normal/ORM). Rig with Rigify or Mixamo.
2. **Animations**: idle, walk, run, crouch, aim, fire, reload, hit, death (non-graphic), vault. Export `.glb`, import as `AnimationLibrary`.
3. **Swap-in contract**: a `.glb` scene with an `AnimationPlayer` replaces `SoldierModel`; keep `set_motion(speed)` and `play_fire()`.
4. **Environment kits** (modular, 2 m grid): Alexandrian façades with balconies/shutters, warehouse kit, quay kit,
   Bedouin tents, rail kit, desert rocks. Trim sheets + 1–2 texture atlases per kit for mobile draw calls.
5. **Weapons**: rifle, SMG, pistol, grenade — first-person arms rig + 3rd-person versions.
6. **Audio**: Foley, period radio, muezzin at dusk (respectful use), Alexandria port ambience, Egyptian Arabic VO.
7. **Performance budget (mid Android, 2023)**: ≤ 150k tris on screen, ≤ 150 draw calls, 1 directional + ≤ 4 omni lights,
   30 fps locked, 60 fps option on high-end. Desktop: consider Forward+ renderer with SDFGI/SSAO.

## Asset licences
Only CC0 / self-made / properly licensed assets (Poly Haven, ambientCG, Quaternius, Kenney are CC0).
Noto Kufi Arabic font: SIL OFL 1.1 (see `assets/fonts/`).
