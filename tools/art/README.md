# Unit animation calibration

The transparent frame sequences under `graphics/units/player/units/` are used
directly by `Combatant.UNIT_ANIMATION_CONFIGS`. Archer, Priest, Summoner,
Warrior, Shieldbearer and the summoned Creature have 16-frame `walk`, `attack`
and `death` sequences. Priest and Summoner also have a 16-frame `skill` sequence.

After replacing these images, regenerate their body anchors from the project root:

```powershell
& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path . --script res://tools/art/generate_allied_frame_offsets.gd
```

The generator writes only `combat/allied_frame_offsets.json`; the existing
Hero/Militia anchors in `combat/unit_frame_offsets.json` are separate. It uses
image alpha, preserves green details, anchors the lower body, and keeps the
death animation's original pose origin so falling motion is retained.

Scale, ground offset, health-bar height and animation FPS are configured in
`combat/combatant.gd`. Soldiers use a common 128px visible standing/walking height;
Heroes use 156px and non-troll summons use 83.2px (+30% from 64px).
Enemy ogres use 192px (+50% from 128px), while enemy trolls stay at 128px.
Troll summons (Bog Spawn) retain their original 64px size. Race is identified by
content tags; the unchanged-troll rule has priority. Placeholders follow the same categories.
`combat/unit_visible_sizes.json` records measured source-pixel silhouette heights,
excluding transparent canvas and chroma-key background. The runtime uses the median
walking height for a stable scale, so changing pose does not resize the body every
frame. Animation-specific canvas compensation still applies to attacks. Ground
anchors and health bars follow the normalized size. After replacing artwork, run:

```powershell
& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path . --script res://tools/art/generate_unit_visible_sizes.gd
```

The generator measures source pixels locally; combat never scans image pixels.
The config's legacy `reference_height` is only a fallback for new, unmeasured art.

Gluttony/Lust attack canvas compensation is calibrated from lowered-weapon poses
(`animation_scales.attack`: 2.2 / 4.15), so a raised weapon does not hide a shrinking
body in the animation's median bounds. Scaled animations retain the standing body
anchor via `_scaled_animation_anchor_correction`; the multiplier stays fixed for
the whole animation. `test_allied_animations` checks both size transitions and facings.

`CombatSession.deliver_ability` starts a caster's `skill`
animation at actual ability delivery. This visual overlay does not delay the
effect, change cooldowns or alter autonomous simulation.

Actual locomotion always switches to walking, clearing a stale cast or raised-weapon
pose. A basic attack instead uses a simulation-defined planted swing interval:
its selected target is locked until delivery, even if the target leaves reach.
Ranged retreats face travel direction and turn toward the target only when stopped.

Regression: `res://tests/test_allied_animations.gd`.

## Ranged weapon emission

All nine ranged visuals have `projectile_tip` in the animation config, measured
in texture pixels at `projectile_frame` (held weapons) or `attack_impact_frame`.
The selected release pose reaches its impact frame at simulation windup delivery;
Pride/Envy then hold that frame. Projectile origins sample the authored frame and
offset table, independently of current rendered frame, facing or visibility.
Mirror the calibrated offset for left-facing targets. Preserve this deterministic
path when editing presentation; the headless simulator uses it too.

Test: `res://tests/test_combat_vfx.gd`. It checks the actual drawn release tip,
mirroring, hidden/changed render poses and seeded replay with presentation ticks.

## Enemy animation sequences

All eight enemies have 30 transparent PNG frames for walking, attacking and death
under `graphics/units/enemies/`. Iron Warden also has 30 `spell` frames, mapped to
the runtime `skill` animation. The folder mapping follows the authored names:

| Persistent content ID | Folder |
|---|---|
| `enemy.raider` | `brute` |
| `enemy.troll_berserker` | `berserker` |
| `enemy.ogre_bonebreaker` | `bonebreaker` |
| `enemy.summoner` | `hexer` |
| `enemy.troll_priest` | `witch doctor` |
| `enemy.bog_spawn` | `bog spawn` |
| `enemy.iron_warden` | `iron_warden` |
| `enemy.bog_king` | `mugrot` |

After changing enemy art, regenerate sizes first, then their separate anchor table:

```powershell
& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path . --script res://tools/art/generate_unit_visible_sizes.gd
& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path . --script res://tools/art/generate_enemy_frame_offsets.gd
```

`combat/enemy_frame_offsets.json` stores all 750 frame offsets and body anchors.
The measurement band is positioned relative to feet and standing height, so a
raised weapon does not shift it. A trimmed lower-body centroid and a short temporal
filter stabilize walking/attack/cast frames. Death uses a fixed first-frame origin,
preserving the fall and the corpse. The allied anchor tables are independent.

Enemies use a stable 192px visible walking height for ogres and 128px for trolls;
non-troll summons use 83.2px, while summoned trolls remain 64px.
The alpha shader removes magenta spill only at cutout edges;
green details and opaque purple magic remain. No image pixels are scanned each frame.

`attack_impact_frame` in each animation config divides the attack into windup and
recovery: the impact pose matches simulation delivery, and the tail fits the
remaining motion-lock interval. This never changes cooldowns or damage timing.
`skill_directory` maps differently named source folders; `reactive_skill` lets
Iron Resolve show the authored spell when the threshold guard activates. A guard
triggered while walking queues only the visual until the unit stops.
Boss ground telegraphs are drawn at the feet rather than across the new body art.

Regression: `res://tests/test_enemy_animations.gd` (every frame, both facings,
visible height, attack phase timing, late presentation, reactive cast and death).
