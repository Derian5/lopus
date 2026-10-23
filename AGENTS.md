# Project Context

## What This Is

`Can Be Only One Hero` is a single-player PvE roguelite RPG autobattler built with Godot 4.7 for a PC/Steam demo. The player prepares three Heroes and an army of mortal Soldiers, assigns Jobs, buys abilities and items, studies the next encounter, and then watches a fully autonomous real-time battle. Soldiers can die permanently; Heroes can be revived, but one Hero must be executed after each major act until only one remains.

The core loop is: build the army, watch the battle, understand the result, and rebuild. Combat readability, deterministic simulation, statistics, and explainable post-battle progression are core gameplay features.

## Project Map

- `main.tscn` and `main.gd`: application flow and screen transitions.
- `content/definitions/`: reusable Resource schemas and ability effects.
- `content/demo/`: designer-authored `.tres` content loaded recursively by `ContentRegistry`.
- `data/runtime/`: mutable run state, inventory, Market, save/load, and management transactions.
- `combat/`: snapshots, autonomous combat simulation, events, statistics, and results.
- `ui/`: Management, combat overlays, post-battle, execution, and shared controls.
- `tests/`: standalone headless Godot regression scripts.
- `gamedesign.txt`: high-level game design document.
- `GAME_DESIGNER_GUIDE.md`: authoritative guide for content fields and designer workflows.
- `production plan.txt`: demo scope and production plan.

## Architecture Rules

- Static gameplay content is data-driven. Add definitions under `content/demo/`; do not hardcode content IDs into combat logic unless they identify a true global system resource.
- `ContentRegistry` recursively registers `ContentDefinition` resources. IDs are global and persistent in saves, so do not rename shipped IDs casually.
- Content Resources must not contain runtime `Node` or `NodePath` values.
- Persistent state belongs under `data/runtime/`. Combat operates on `CombatUnitSnapshot` copies and must not mutate the roster directly.
- Apply post-battle changes through `CombatResult` and `CombatResultApplicator` so rewards and permanent deaths remain idempotent.
- Use the run's persisted RNG streams or the seeded combat RNG. Avoid global randomness in gameplay.
- Jobs share one `JobBuildState`; an individual Soldier does not own a separate ability build.
- Preserve designer-authored balance values unless a task explicitly asks for balance changes.
- Never order by comparing typed `StringName` values with `<` / `>` or `Array[StringName].sort()`: Godot compares StringNames by memory address, so the order (and with it a seeded run) changes between launches. Compare `String(a.id) < String(b.id)`.

## Verification

Run a test from the repository root with:

```powershell
& "C:\Program Files (x86)\Steam\steamapps\common\Godot Engine\godot.windows.opt.tools.64.exe" --headless --path . --script res://tests/test_name.gd
```

Run Godot tests sequentially because concurrent starts can race on `.godot/global_script_class_cache.cfg`. After adding a new `class_name`, refresh the project once with `--headless --editor --path . --quit` before running tests. Choose targeted tests first, then related Market, save/load, combat result, and route regressions.

## Traffic Budget

The developer has a limited internet connection. Minimize data transferred between the local machine and any remote/cloud environment.

- Read, search, and edit project files in place on the local machine (local shell). Do not upload files to a remote workspace just to read or edit them.
- Never upload the whole project or large archives. If a remote-only step is unavoidable, transfer only the specific files it needs and ask first if the total exceeds ~2 MB.
- Do not run Godot tests remotely by default. Provide the exact test command; the developer runs it locally and shares the output.
- Do not inspect large images (atlases, portraits, sprite sheets) or produce screenshots without asking. If an image is required, downscale or crop it locally first to a few hundred KB.
- Avoid browser automation and screen-control tools; they stream screenshots continuously.
- Do not download large tools or dependencies on the local machine without asking.
- Prefer small text diffs and concise output over sending full files back.

## Recent Changes (October 2026 session)

Summary of systems added or reworked recently. Read this before touching combat feel, Act I content, ability text or Job progression. Details for designers are in `GAME_DESIGNER_GUIDE.md` (sections on Act I difficulty, knockback, ability descriptions, purchased Job skills and veterancy).

### Combat feel and visuals
- Sprite jitter during walk/attack was fixed with stable screen-space body anchors (`combatant.gd`, `_update_sprite_facing`). `test_combat` checks `hero.thorn_warden` anchors; that check fails only with placeholder sprites.
- Hit knockback is no longer fixed: `Combatant.damage_knockback_for(damage)` scales with damage / Max HP (`damage_knockback_distance`, `damage_knockback_reference_percent`, `damage_knockback_max_distance`), clamped to the arena.
- Attacks: basic/replacement swings lock their chosen target at windup start, cannot be redirected by AI/taunts or cancelled by the target leaving range, and hold position through the fixed `ATTACK_SWING_FRACTION` interval. Ready ranged attacks do not wait for a navigation goal. Retreats use walk animations facing travel direction; ranged units stop and turn back to shoot after reaching safety. `test_committed_attacks` covers this cycle, including a missed presentation windup.
- Movement: automatic formation spacing is up to 96 px. Soft allied personal space is separate from collision radii and steers moving units only. Melee fighters reserve deterministic approach sectors; ranged recovery uses 55%/80% retreat hysteresis and a committed destination. Basic targets switch only for a meaningful gain. Navigation state and timers belong to simulation steps, never `_process`; `test_combat_movement` checks settling and replay equality with different presentation ticks.
- Melee swings (including replacement attacks, retreat counters and frenzy) start only beside their target: `abs(dy) <= 0.6 * abs(dx)`. Twelve approach points occupy two lateral fans (±20°); neighbouring reservations account for physical clearance. Root does not bypass this rule. Committed swings still complete after the target moves; ranged attacks have no side restriction.
- Melee arrival tolerance is valid only when the current position is inside attack reach and a lateral sector. A cached approach point can remain valid after a small target move while the 8px arrival circle extends out of reach; do not stop there (it bypasses the stuck timer and leaves `MOVE_INTO_RANGE` idle). `test_tutorial_combat_activity` checks the first encounter across three Hero trios and three arena sizes.
- Projectiles keep flying to the target's last position after the target dies instead of vanishing.
- The battle preview no longer shows the attack range of a unit that is not being dragged.
- Soldier veterancy is visible without clicking: `ui/common/veterancy_insignia.gd` (`VeterancyInsignia`) draws chevrons: ranks 0-2 = 1-3 bronze, 3-5 = 1-3 silver + bar, 6+ = gold + star (rank 0 shows one chevron; -1 hides the insignia). Used left of the health bar in combat (not for Heroes), on battlefield preview tokens, in Management soldier rows and on the portrait.

### Post-battle
- The XP bar in `ui/post_battle/` is split into three coloured parts: damage, tanking and healing XP.

### Act I content and difficulty
- Act I = 12 battles + boss (Bog King) on battle 13, ~25 encounters in `content/demo/encounters/act_1/`, heavy use of reinforcements. Lore: Wasteland ogres and trolls. New enemies and a mini-boss (Iron Warden); every enemy has an ability (`content/demo/abilities/enemies/`).
- Difficulty ("hard" curve): `RouteDefinition.act_one_enemy_power_curve[battle_index]` x encounter `enemy_power` = power p. Enemy HP x p^0.85, damage x p^1.15, applied by `CombatDemoFactory.apply_enemy_power(stats, power, source)`, which also records breakdown steps.
- Enemy stat tooltips in combat show the breakdown ("Act threat (battle N): xA", "Encounter strength: <name>: xB") so players understand why the same enemy differs between fights.
- Encounter cards were redesigned: enemy count via `EnemyToken` medallions (role glyphs), reward shown prominently.
- `tools/balance/gen_act1_content.py` generates Act I enemies/encounters/enemy abilities (incl. their description `TEMPLATES`). It auto-detects the project root; running it OVERWRITES those `.tres` files, so edit the script, not only the generated files. `tools/balance/balance_sim.gd` simulates encounters for tuning. Delete the stray `tools/balance/content/` folder if it still exists (created by an old run from the wrong directory).
- All Hero `.tres` base stats were nerfed: Max HP and damage halved, attack speed -0.3, Wrath movement 120 -> 94. Heroes now lose some test battles: `test_combat_results` (integrated victory Gold) and `test_stage15` (battle 1) fail for that reason; Act I enemy power may need retuning.
- Militia's new innate made early fights easier (Brute Patrol, Marching Warband); not retuned yet.

### Jobs
- Count-based professionalism was removed. The five two-level Job skills are bought in the Market: Level I costs 150 Gold, Level II costs 250 and references Level I through `AbilityDefinition.upgrades_ability_id`. Both IDs live in `Job.available_ability_ids`; upgrades replace the equipped preceding level in the shared `JobBuildState`. Legacy IDs containing `professionalism` remain stable for saves/content. Warrior Bloodthirst I = 50% basic-attack lifesteal; II adds shared Sundered Armor (-5 armor per hit, 6 s, max 10 stacks).
- Militia innate `militia_strength_in_numbers` (`Job.innate_ability_ids`): `NearbyAllyStatBonusEffect`, +3 armor per nearby Militia within 160, max 5. Applied in `Combatant._calculate_effective_stat` with a breakdown step.
- New effects: `content/definitions/effects/basic_attack_lifesteal_effect.gd`, `on_hit_status_effect.gd`, `nearby_ally_stat_bonus_effect.gd`; runtime hooks in `combatant.gd` (`add_passive_basic_lifesteal`, `add_on_hit_status`, `set_nearby_ally_stat_bonus`, statuses applied in `record_successful_basic_hit`).
- Management shows innate (badge "I") and every purchasable Job skill level: unpurchased previews show NOT BOUGHT / NOT PURCHASED with a padlock; purchased older levels are dimmed as REPLACED. The Market uses skill artwork and labels upgrades. `ContentButton.describe_job` lists INNATE and MARKET SKILLS. `test_job_skill_market` covers purchases, prerequisites, upgrade replacement, UI and Save/Load.

### Ability descriptions (important for any new ability)
- `AbilityDefinition.description` is a TEMPLATE rendered by `ui/common/ability_text.gd` (`AbilityText`). Never hardcode numbers: use tokens `{e0.damage}`, `{e1.status.default_duration}`, `{area}`, `{search}`, `{cast}`, `{icd}`, `{recent}`, products `{a*b}`, formats `:pct :inv_pct :bonus_pct :abs`.
- Colour tags with icons: `[dmg] [heal] [shield] [cc] [buff] [debuff] [gold] [summon] [xp] [kw]`. Icons live in `graphics/ui/ability_icons/`.
- Do not write cooldown, range or radius in the text: the header (`AbilityText.stat_line`) shows them with icons. Write units glued to the token (`{e0.duration}s`, `{x:pct}%`); they become part of the number.
- Rendering: known level -> one number; upgrade preview (`compare_level`, used by the hero level-up card) -> "old -> new"; no level -> `200/400/600/800` in one style. `AbilityText.plain()` gives text without BBCode.
- Entry points: `AbilityText.tooltip/type_line/stat_line/render/plain`; `ContentButton.describe_ability_definition(ability, level)`; `AbilityDefinition.for_hero_level()` sets meta `hero_level`.
- Tooltips are now RichTextLabel (`ui/common/content_tooltip.tscn`, width 400); the theme defines RichTextLabel normal/bold fonts. The hero ability reward popup (`hero_ability_reward_popup.gd`) uses side-by-side cards (`_offer_card`).
- Several tests assert exact BBCode fragments (`test_management_ui`, `test_job_professionalism`, `test_priest_heal`, `test_despair_abilities`, `test_shieldbearer_job`); update them when changing the formatter.

### File names
- Enemy and Encounter `.tres` files are named after their in-game display names (e.g. `enemies/ogre_brute.tres`, `encounters/act_1/ogres_on_the_road.tres`). Content IDs were NOT renamed (`enemy.raider`, `encounter.tutorial_volley`, ...) because IDs are stored in saves; look content up by ID, not by file name.

### Allied summons
- Units summoned for the player (Summoner Job: brawler, shooter, amalgam; Necromagister's Skull: skeleton) live in `content/demo/summons/`. `content/demo/enemies/` holds only the 8 enemies: Ogre Brute, Troll Hexer, Troll Witch Doctor, Ogre Bonebreaker, Troll Berserker, Bog Spawn (summoned by Hexer and Mugrot), Mugrot the Bog King, The Iron Warden. Juggernaut, War-Drummer, Spear-Thrower and Bog Spitter were removed; `test_massive_ogre.gd` went with them.

### Hero items (42 items, 5 categories)
- Combat inspector item slots use `AbilityCooldownIcon`, like ability slots. Timers are read through `ItemDefinition.ability_ids`: active cooldowns from `combatant.ability_cooldowns` (CDR-adjusted total), periodic heals from `combatant.items.pulse_heals`. The longest remaining timer is shown for a multi-ability item; untimed passives/per-target proc lockouts do not create a global cooldown overlay. UI refresh is read-only. Test: `test_item_cooldowns` (includes rendered pixel checks without `--headless`).
- All items are generated by `tools/items/gen_items.py` (items in `content/demo/items/<category>/`, item abilities in `content/demo/abilities/items/`, skeleton summon `content/demo/summons/summoned_skeleton.tres`). Edit the script tables and rerun; it rewrites those folders. Icons are category placeholders in `graphics/ui/item_icons/`.
- `ItemDefinition` gained `category`, `ability_ids` (item abilities join `snapshot.abilities` in `CombatSnapshotBuilder.build_hero`; hidden from the selected-unit ability row via the `item` tag) and `allowed_hero_ids` (unique Sin items; `is_compatible_with_hero` enforces it, so the Market only offers them to that Hero).
- Secondary stats on `CombatStats`/`StatModifier`: crit_chance, crit_multiplier, lifesteal, dodge, hp_regen, cooldown_reduction, damage_taken, armor_penetration. New operation `ADD_PERCENT` (summed per stat, applied once). Dodge and CDR stack with diminishing returns (caps 60% / 75%). Combat hooks: crit in `Combatant.take_damage` (basic attacks), dodge in `CombatSession.should_dodge`, lifesteal in `apply_basic_attack_lifesteal`, CDR in `Combatant.cooldown_for`, regen ticks in `CombatantItemRuntime.update`.
- Item mechanics: effects in `content/definitions/effects/items/`, per-unit state in `combat/item_runtime.gd` (`Combatant.items`). Statuses support `causes_fear` and `grants_invulnerability`; charm swaps `snapshot.team` temporarily, and victory checks use `items.home_team()`. Run-permanent gains (Insatiable Maw) go through `statistics.record_permanent_stat_gain`, and the snapshot carries previous totals in `permanent_gains`.
- `tests/test_items.gd` covers every item mechanic plus a smoke battle with all items.
- The numbers follow the design table as-is (the developer chose not to scale them), so item bonuses dwarf the halved Hero base stats; balance follow-up is expected.

### Balance Lab (run simulator)
- `tools/balance/run_sim/`: plays whole runs headless through the real services with a scripted bot (styles: heroes, one_hero, army, one_job, two_jobs, nothing) and writes CSV/JSON/HTML reports (styles, Hero winrates, Encounter danger, every run). Window: `balance_lab.tscn` (F6); CLI: `sim_cli.gd`. See its README.
- Combat is stepped by hand at 1/60 s (`RunSimulator._step`). `Combatant` moves with `_slide(delta)` instead of `move_and_slide()` so movement never depends on frame time; keep it that way or the simulator stops being deterministic.

### Balance targets
- Tuned with Balance Lab to ~30% average winrate across all six bot styles (48-run batches): `act_one_enemy_power_curve`, new `act_two_enemy_power_curve` (RouteDefinition), encounter `enemy_power`. Enemies can hunt the back line: `EnemyDefinition.targeting_mode = "back_line"` (Troll Berserker) and `TargetingPolicy.RANDOM_BACK_LINE_ENEMY` (Bone-Breaking Leap). Re-run Balance Lab after big content changes.

### Balance Lab speed
- `tools/balance/run_sim/sim_parallel.gd` + `sim_worker.gd` run a batch in several headless Godot processes (`workers=` / "Parallel processes"); results equal a single-process run.
- Combat hot paths: `_calculate_effective_stat` builds tooltip entries only when `entries != null`; `CombatSession.any_*_aura` flags (set by the aura effects) skip aura scans; separation/overlap use a squared-distance pre-check. Keep stat queries cheap: they run thousands of times per second.
- Fixed: encounter/market/event/reward ordering sorted StringNames by address (non-reproducible seeds).

### Startup loading
- Normal launch starts at `ui/loading/startup.tscn`: display the loading screen, await `StartupAssets.prepare()`, then open `main.tscn`. `autoload/startup_assets.gd` retains strong Resource references for the application lifetime, prepares every `Combatant.UNIT_ANIMATION_CONFIGS` animation, authored offsets, legacy/chroma and standing-foot scans, every `CombatVfx.ATLASES` SpriteFrames/material, UI artwork and battlefield scenery. Add animation/effect entries to those existing tables; the loader discovers them automatically.
- Script-heavy `main.tscn` loads on the main thread after the loading screen is shown (threaded first load leaks native RefCounteds in Godot 4.7.2). Bulk media uses a bounded threaded queue; headless uses time-sliced main-thread loading because dummy texture storage is unsafe for parallel RID creation. `ui/loading/render_warmup.gd` draws textures, materials/light variants and fonts in a hidden SubViewport and starts video decoding before the menu. Headless skips GPU preparation.
- Preparation is explicit and idempotent: CLI tests and Balance Lab do not eagerly warm the entire game. Direct `main.tscn` instantiation retains its previous synchronous menu behavior. Tests: `test_startup_assets` (cache coverage, warm unit creation, no new pixel scans) and `test_startup_flow` (loading -> menu -> Hero selection -> menu). Run without `--headless` to exercise GPU preparation; timings are available in `StartupAssets.report`.

### Unit animation
- All 8 enemies use transparent 30-frame walk/attack/death sequences from `graphics/units/enemies/`; Iron Warden's `spell/` maps to `skill`. Enemy anchors live in `combat/enemy_frame_offsets.json`, generated by `tools/art/generate_enemy_frame_offsets.gd` after regenerating visible sizes. Lower-body/feet anchors stabilize each frame; death retains the original origin. `unit_alpha_sprite.gdshader` despills magenta only along alpha edges. Enemy `attack_impact_frame` fits the authored impact to simulation windup; recovery uses the remaining motion lock. `reactive_skill` shows Iron Resolve's spell on threshold guard (visual queued while moving). Boss rings/charge are on the ground marker. Test: `test_enemy_animations`.
- Visible standing/walking silhouette heights: Soldiers 128px, Heroes 156px, enemy ogres 192px (+50%), enemy trolls 128px, non-troll summons 83.2px (+30% from 64px). Troll summons (Bog Spawn) retain 64px. Race comes from EnemyDefinition tags, with the unchanged-troll rule taking priority. `combat/unit_visible_sizes.json` contains measured source heights (transparent/chroma-key margins excluded); regenerate with `tools/art/generate_unit_visible_sizes.gd` after replacing art. Scale stays stable across frames; authored attack canvas compensation remains. Placeholder bodies follow the same size categories.
- Envy (`hero.army_support`) has `"despill_green_edges": true`: its frames already have real alpha and a green costume, so instead of the chroma-key shader (which bleached the greens) it uses `unit_alpha_sprite.gdshader` with `despill_green` (green fringe removed only along cut-out edges). `chroma_key` stays true for feet scans and frame offsets.
- Gluttony/Lust attack canvas multipliers (2.2 / 4.15) are calibrated against neutral, lowered-weapon frames, not the whole attack's median height. `_scaled_animation_anchor_correction` preserves the standing body anchor when applying an animation-specific scale; do not vary scale per frame to follow a raised weapon. `test_allied_animations` checks their walk/attack/idle size transitions.
- `Combatant.ANIMATION_SPEED = 1.5`: unit animations are accelerated in `_build_unit_sprite_frames`. Basic attack poses fit their remaining simulation-defined standstill interval; movement locks never depend on a renderer frame or an AnimatedSprite signal. The opening walk delay uses authored fps and is cleared after the first action so subsequent retreats always animate.
- `"attack_hold": [loop_start, hold_frame]` in `UNIT_ANIMATION_CONFIGS` (Envy, Pride): the first shot plays 0..hold, next shots loop loop_start..hold, the weapon stays raised between stationary shots (`ATTACK_HOLD_GRACE`). Walking clears the held pose. Attack serials ensure the pose still starts if rendering missed the short windup.

### Combat VFX (Arcaidia Effector)
- Sources: `Arcada Effector_1.0 (1)/library/CBO *.json`, generated by `Arcada Effector_1.0 (1)/gen_cbo.py` (edit the generator, re-run it, export the atlases from the editor's Atlas tab or headlessly via `AFX.Atlas.build`). Atlases: `graphics/effects/vfx/<id>.png`; frame layout table: `combat/vfx/combat_vfx.gd` (`ATLASES`, update it when cols/frames/cell size change).
- `CombatVfx` (static helpers, projectile/colour tables) + `CombatVfxDirector` (child of CombatSession, listens to `combat_event_emitted`: ability cast sigil, ability hit burst, heal sparkle, death soul, summon portal). Melee hits (`CombatSession.spawn_hit_vfx`), shot hits/launch flash (projectile.gd), area slams (`spawn_area_vfx` in leap/ground slam/radius damage/area projectiles) and footstep dust (`Combatant._update_walk_dust`) call the helpers directly.
- Pipeline: `python gen_cbo.py` (writes library/CBO *.json) → export atlases (editor Atlas tab, or headless `AFX.Atlas.build`) → `python cbo_clean_atlas.py <in> <out>` (fades every cell to transparent at its borders; needed because most effects are drawn additively, see `CombatVfx.ADDITIVE`) → copy PNGs to graphics/effects/vfx and update `CombatVfx.ATLASES`. Death = `death_smoke` (normal) + `death_soul` (additive); area hits = `slam_dust` + `slam_ring`.
- Lighting: magic shots carry a `PointLight2D` (`CombatVfx.SHOT_LIGHTS`); hits, casts, heals, deaths, summons and slams fire short `CombatVfx.flash_light` flashes into `CombatSession.light_layer` (max `MAX_FLASH_LIGHTS`). Additive effects are unshaded so lights only brighten the ground, units and smoke.
- Shot origin: all 9 ranged visuals have `projectile_tip` (texture pixels) and an authored release pose in `UNIT_ANIMATION_CONFIGS` (`projectile_frame` or `attack_impact_frame`). `_calibrated_projectile_origin` samples that pose and its measured offsets, never the live renderer frame/facing/visibility; the Balance Lab uses the same origin. Legacy `HERO_PROJECTILE_TIPS` / frame tips remain fallbacks. Ordinary ranged windups and Envy/Pride held raises now reach their release pose at simulation delivery, without changing attack timers.
- Ability/status VFX are data-driven through `AbilityDefinition.presentation_style`, `projectile_vfx` and `StatusDefinition.presentation_style`. `spell_shape_vfx.gd` adds style-specific accents; `projectile_trail.gd` adds fading ribbons/embers. Fire Arrow uses the arrow atlas plus fire, warm light and burn presentation rather than magic_orb. `unit_status_vfx.gd` owns attached flames, poison, roots, control, shields and charm; it reads statuses only, stops on cleanse/expiry/death, and caps persistent burn lights at `MAX_STATUS_LIGHTS` (8). Periodic ticks do not create repeated generic explosions. Enemy style metadata is also preserved by `tools/balance/gen_act1_content.py`. Test: `test_combat_vfx` (9 tips, mirrored/hidden/late poses, burn/light lifecycle and real-Hero replay equality with/without presentation ticks).
- Fire Arrow shot (October 22): two atlases from `gen_cbo.py` ("Fire Arrow" section) play together: `fire_arrow` (solid arrow with a charred shaft and smoke, normal blend) and `fire_arrow_glow` (additive: white-hot head, flame tongues streaming back, long flame tail, falling embers), the glow drawn 1.3x larger as a child of the projectile sprite. The shot light is stronger (`SHOT_LIGHTS.fire_arrow`), the launch puffs a small `fire_burst` with firelight, and `projectile_trail.gd` draws a wider heat ribbon (150 px) for it.
- Burn/blood (October 22 rework; the earlier `CBO Burning Veil` / `Ignition Burst` / `Blood Impact` / `Blood Ground` atlases are no longer registered, `bleeding_drips` stays). Sources in `Arcada Effector_1.0 (1)/gen_cbo.py` ("fire and blood" section): `CBO Burn Loop` (additive body fire: clinging flames, rising tongues, embers; feet 90 px below the cell centre), `CBO Burn Smoke` (normal, shaded), `CBO Fire Burst` (additive flare; its ground ring 60 px below the centre), `CBO Blood Spurt` (drops thrown toward +X, flipped toward the blow, never rotated) and `CBO Blood Burst` (bleed ticks). Export as in the pipeline above (`cbo_clean_atlas.py` edge fade).
- Burning (`unit_status_vfx.gd`): front flames (`burn_sprite`, additive, ~55%) + smoke on the status node, `burn_back` (a child of the unit at index 0, drawn behind the sprite) so the body stays readable; size from `_height()`. Ticks flare up via `CombatSession.spawn_fire_tick` (throttled). Fire areas (`apply_projectile_impact` with fire style) use `_spawn_fire_area_vfx`; `spawn_spell(&"fire")` is a `fire_burst` plus a scorch mark.
- Blood: `CombatVfx.spawn_blood` (every damaging hit: `BloodHit`; bleed ticks: `BleedPulse`) skips units whose definition has a `BLOODLESS_TAGS` tag. Where drops land, `CombatSession.add_ground_decal` leaves stains in `decal_layer` (global z 1, before `Units`, so under shadows) for the whole battle (max `MAX_DECALS`, oldest removed); deaths leave a spreading pool (`spawn_blood_pool`); fire leaves scorch marks. Decal art: `graphics/effects/vfx/ground_decals.png`, generated by `tools/vfx/gen_decals.py`.
- Hurt look: below `HURT_THRESHOLD` (40% HP) `unit_status_vfx` drips blood (`spawn_blood_drip`, faster when worse; always while bleeding) and writes `Combatant.condition_hurt` / `condition_burn`; the chroma and alpha sprite shaders (`condition_look`) drain colour with a red heartbeat pulse and give burning units a scorched, flickering glow (plain sprites get a modulate fallback).
- Lights: flash lights are elliptical ground pools (`get_ground_light_texture`) with a 35 ms rise and a cubic tail; shot lights use a softer, gaussian-like round texture; burning units carry a flickering pool of firelight (`fire_flicker`, still capped by `MAX_STATUS_LIGHTS`).
- Cloud visual checks (no editor): `tools/vfx_preview/condition_preview.gd` (burning, bleeding, hurt units, blows; env `OUT`).
- Bleeding: status `presentation_style = bleed` drives the attached `bleeding_drips` loop and one stronger pulse per real tick, coalescing simultaneous stack events; preserve the field in `tools/items/gen_items.py`. Zero/full-shield damage draws no blood. Flame phases are decorrelated from adjacent unit IDs without gameplay RNG. Test: `test_burn_blood_vfx`.
- Visual check: open `tools/vfx_preview/vfx_preview.tscn`, F6 — it plays scripted battles and saves frames to `tools/vfx_preview/shots/` (ignored by the importer), then quits.
- Visual nodes are presentation only and skipped with `CombatSession.vfx_enabled = false` in the Balance Lab. Calibrated projectile origins are gameplay and must remain identical in both modes; do not gate them on VFX or current sprite visibility. The old HeroAttackVfx and its atlases were removed.

### Veterancy in battle
- Player Soldiers rank up mid-battle: `CombatSession.veterancy_watch` holds each Soldier's pre-battle `CombatUnitSnapshot.veterancy_xp`; after every damage/healing event `_check_veterancy` adds the live contribution (`ProgressionDefinition.contribution_breakdown`, same as the post-battle result; summons credit their summoner) and calls `Combatant.gain_veterancy_level` (rank growth applied to battle stats, extra max HP granted as health, Veterancy-scaled heals rescaled), then emits `CombatEvent.VETERANCY_GAINED`. The post-battle result recomputes the same total, so ranks always agree.
- Presentation: `CombatVfxDirector._on_veterancy` plays `veterancy_blessing` (CBO Veterancy Blessing: golden light shaft, spark rain, burst, ground ring, halo, rising motes; feet 112.5 px below the cell centre) with warm lights; the unit shows a rising "RANK UP" and a pulsing insignia (`veterancy_banner_timer`). Test: `test_battle_veterancy`.

### Animated battlefield
- Readability: ally/enemy HP bars are green/red with an unshaded overhead material; shields have a separate blue strip, recent damage a presentation-only trail, and hard CC gets a short label. Selection uses `combat/unit_ground_marker.gd` at the feet, below bodies. Enemies without animation use `EnemyToken` role medallions, centred before the first layout pass. The battle inspector hides empty slots, fits its content and has a close button; the header shows encounter/time. VFX overlap brightness is controlled by `CombatVfx.OPACITY` and reduced light energy. Regressions: `test_combat_visual_readability`, `test_combat_render_order` (rendered pixel checks).
- `graphics/battleground/battleground_back.ogv` (Theora, made from `arts/v1/battleground_back.mp4` with ffmpeg; the last 0.5 s cross-fade into the start so the loop has no seam) plays behind the arena; `battleground_front.png` (from `arts/v1/battleground_front_parallex.png`) is drawn in front of units (z 90, under health bars) and drifts against the mouse. `CombatSession._setup_scenery/_update_parallax`, constants `FOREGROUND_PARALLAX`, `BACKDROP_PARALLAX`, `PARALLAX_OVERSCAN`. Not created when `vfx_enabled` is false (Balance Lab). The old `graphics/battleground.png` is still used as fallback and by the management battlefield preview.
- Mood: the foreground is tinted dark (`FOREGROUND_TINT`), a vignette darkens the arena edges (`VIGNETTE_Z` 85, unshaded), every unit has a soft ground shadow (`Combatant.ground_shadow`, global z 1, at `feet_position()` = bottom of the current sprite frame). Use `feet_position()` for anything placed on the ground.
- Spear wielders (`CombatVfx.SPEAR_JOBS`: militia, shieldbearer) hit with `spear_sparks` plus `spark_lights` (tiny lights flying off on ballistic paths).
- Walkable area: `CombatSession.get_arena_bounds()` starts at `WALKABLE_TOP_FRACTION` (0.21) of the arena height, so units stay on the painted ground below the horizon (gameplay: the arena is ~17% lower than before; formations and the Balance Lab use the same bounds).
- Terrain: `combat/arena_geometry.gd` subtracts four normalized `CUTOUTS` from those bounds (upper side ruins and lower corner piles). Radius-inset polygons, projection, step collision/wall sliding and a cached deterministic visibility graph are shared by combat, FormationService, the deployment preview and Balance Lab. Keep it active with `vfx_enabled = false`. All placement/displacement paths must use this geometry; entry waves use open edge segments and additional inward columns. Preview shading shows cutouts; runtime combat has no debug overlay. Tests: `test_arena_geometry`, `test_formation`, `test_tutorial_combat_activity`, `test_combat_movement`.
- Godot only plays Ogg Theora video: convert new videos with `ffmpeg -i in.mp4 -an -c:v libtheora -q:v 8 out.ogv`.

### Management screen (army + Market)
- No Inventory section. The roster shows one card per Hero (`_add_hero_card`) with its six item slots; gear moves by dragging a slot onto another Hero's slot (swap) or card (first free slot). `ArmyBuildService` handles `equipped_item -> equipment` (`_move_equipped_item`, atomic on the staged state; both Heroes must be able to use what they receive) and `equipped_item/inventory_item -> sell`. Target `slot_index` -1 means "first free slot"; bought gear always takes a free slot.
- Unequipped items (event rewards, old saves) are auto-equipped on refresh (`_auto_equip_spare_items`: selected Hero first, then any compatible Hero with room); leftovers show as "Spare gear" under the Heroes.
- Market: toolbar (reroll + `SellDropSlot`), a hint, then one card per offer (`_market_card`: framed icon with the full tooltip, name, `Tag` kind line, 2-line description, `Stats` flow of icon + value chips, `BuyButton` price, `PinButton`). The whole card is a drag source (`set_drag_forwarding`). Double-click or BUY buys; items go to `_free_item_slot_hero`. Item accents follow `ITEM_ACCENTS` (category); stat icons are `STAT_ATLAS_REGIONS` (atlas) or `STAT_ICON_NAMES` (ability icons).
- Visual check without the editor: `tools/ui_preview/management_shot.gd` (`NITEMS=21 SOLDIER=1` for a full-gear / Job-skill state; under xvfb in the cloud).

### Known pre-existing test failures (not caused by these changes)
test_abilities (AI slot order), test_combat (anchor check with placeholder sprites), test_combat_results ("Post Battle panel shows Gold"), test_hero_ability_rewards, test_hero_selection, test_lust_abilities (base stats), test_stage13, test_stage14 (execution save), test_stage15, test_troll_priest (base stats). After the Hero nerf test_stage14 "Act I Boss is beatable" also fails (balance). Several reflect intentional balance/content changes; update the tests rather than reverting content.
