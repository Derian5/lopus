# Allied unit frame anchors

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
Heroes use 156px and summons use 64px. Placeholder bodies follow the same categories.
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

`CombatSession.deliver_ability` starts a caster's `skill`
animation at actual ability delivery. This visual overlay does not delay the
effect, change cooldowns or alter autonomous simulation.

Actual locomotion always switches to walking, clearing a stale cast or raised-weapon
pose. A basic attack instead uses a simulation-defined planted swing interval:
its selected target is locked until delivery, even if the target leaves reach.
Ranged retreats face travel direction and turn toward the target only when stopped.

Regression: `res://tests/test_allied_animations.gd`.
