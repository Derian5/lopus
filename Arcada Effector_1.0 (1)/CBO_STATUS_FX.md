# CBO burn and blood materials

These are native Arcaidia Effector documents. Open the corresponding new files
in the editor's library to inspect/edit them. Existing user effects and the
original `gen_cbo.py` are independent.

| Library document | Game atlas | Cells / frames | Playback |
|---|---|---|---|
| CBO Burning Veil | `burning_veil.png` | 160x224 / 32, 8 columns | 32 fps loop |
| CBO Ignition Burst | `ignition_burst.png` | 160x160 / 16, 4 columns | 26.67 fps one-shot |
| CBO Blood Impact | `blood_impact.png` | 192x128 / 16, 4 columns | 26.67 fps one-shot |
| CBO Blood Impact Alternate | `blood_impact_alternate.png` | 192x128 / 16, 4 columns | 26.67 fps one-shot |
| CBO Bleeding Drips | `bleeding_drips.png` | 128x160 / 24, 6 columns | 20 fps loop |
| CBO Blood Ground | `blood_ground.png` | 160x96 / 12, 4 columns | 7.5 fps one-shot |

## Design

Burning Veil follows the Flame Pro architecture: charcoal smoke below the fire,
low amber core, flowing smoke-shaped flame mass, detached ribbons, curl fields,
upward guide paths, pixel displacement above the fire and sharp embers above the
displacement. It exports a stationary one-second window (four emission pulses).
The composition is 320x448 with the game foot anchor at `(0, +180)` relative to
its centre: the game sprite's offset is `(0, -90)` at the exported cell scale.
Play the baked fire/smoke in **normal unshaded** mode; its separate warm light
illuminates the unit/ground. Do not replace it with repeated projectile flames.

Blood impacts combine non-glowing liquid trails, falling droplets and fine mist.
The alternate uses another seeded trajectory pattern. Bleeding Drips is a
continuous wound stream; Blood Ground is a fading ground stain. Blood has normal
blending, never additive glow. Ground stains are below bodies. Damage direction
mirrors the spray; large vertical rotations are avoided to preserve downward gravity.

## Rebuild from the game repository root

```powershell
python "Arcada Effector_1.0 (1)/gen_cbo_status_fx.py"
node "Arcada Effector_1.0 (1)/tools/validate.mjs" "Arcada Effector_1.0 (1)/library/CBO Burning Veil.json" "Arcada Effector_1.0 (1)/library/CBO Ignition Burst.json" "Arcada Effector_1.0 (1)/library/CBO Blood Impact.json" "Arcada Effector_1.0 (1)/library/CBO Blood Impact Alternate.json" "Arcada Effector_1.0 (1)/library/CBO Bleeding Drips.json" "Arcada Effector_1.0 (1)/library/CBO Blood Ground.json"
node "Arcada Effector_1.0 (1)/tools/export_atlases.mjs" --out "graphics/effects/vfx" "Arcada Effector_1.0 (1)/library/CBO Burning Veil.json" "Arcada Effector_1.0 (1)/library/CBO Ignition Burst.json" "Arcada Effector_1.0 (1)/library/CBO Blood Impact.json" "Arcada Effector_1.0 (1)/library/CBO Blood Impact Alternate.json" "Arcada Effector_1.0 (1)/library/CBO Bleeding Drips.json" "Arcada Effector_1.0 (1)/library/CBO Blood Ground.json"
```

The batch tool uses the real `AFX.Engine` and `AFX.Atlas.build` in a local
headless Canvas host, verifies two independent renders, then applies the same
three-pixel cell-edge fade needed by the game's atlas pipeline. It requires
Node 22+ and an installed Edge/Chromium (`AFX_BROWSER` can override the executable).
It uses an isolated temporary browser profile with background networking disabled;
it does not open the editor UI or touch user workspace/localStorage. `AFX_TEMP`
can select an existing temporary directory (default: the system temp's `opencode`
directory). Small contact sheets and layout metadata are written there.

After exporting, refresh the Godot imports. Layout registration lives in
`combat/vfx/combat_vfx.gd`. Runtime tests: `tests/test_burn_blood_vfx.gd` and
`tests/test_combat_vfx.gd`.
