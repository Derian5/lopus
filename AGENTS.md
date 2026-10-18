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

Summary of systems added or reworked recently. Read this before touching combat feel, Act I content, ability text or Job progression. Details for designers are in `GAME_DESIGNER_GUIDE.md` (sections on Act I difficulty, knockback, ability descriptions, professionalism and veterancy).

### Combat feel and visuals
- Sprite jitter during walk/attack was fixed with stable screen-space body anchors (`combatant.gd`, `_update_sprite_facing`). `test_combat` checks `hero.thorn_warden` anchors; that check fails only with placeholder sprites.
- Hit knockback is no longer fixed: `Combatant.damage_knockback_for(damage)` scales with damage / Max HP (`damage_knockback_distance`, `damage_knockback_reference_percent`, `damage_knockback_max_distance`), clamped to the arena.
- Retreating ranged units (melee retreat) always face the enemy they flee from; no left/right flicker while attacking during retreat.
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
- Warrior professionalism (thresholds `[3, 6]`): tier 1 `professionalism_bloodthirst_tier_1` = 50% basic-attack lifesteal (`BasicAttackLifestealEffect`); tier 2 adds `OnHitStatusEffect` applying `status.warrior_sundered_armor` (-5 armor per hit, 6 s refreshed, max 10 stacks, ADD_STACKS = one shared instance per target, so all Warriors share the cap).
- Militia innate `militia_strength_in_numbers` (`Job.innate_ability_ids`): `NearbyAllyStatBonusEffect`, +3 armor per nearby Militia within 160, max 5. Applied in `Combatant._calculate_effective_stat` with a breakdown step.
- New effects: `content/definitions/effects/basic_attack_lifesteal_effect.gd`, `on_hit_status_effect.gd`, `nearby_ally_stat_bonus_effect.gd`; runtime hooks in `combatant.gd` (`add_passive_basic_lifesteal`, `add_on_hit_status`, `set_nearby_ally_stat_bonus`, statuses applied in `record_successful_basic_hit`).
- Management shows innate (badge "I") and all professionalism tiers (badges "3+"/"6+") in the soldier inspector: active tier selected, lower tiers dimmed, higher tiers locked with a padlock (`ContentIconButton.locked`) and an unlock hint. `ContentButton.describe_job` lists INNATE and PROFESSIONALISM.

### Ability descriptions (important for any new ability)
- `AbilityDefinition.description` is a TEMPLATE rendered by `ui/common/ability_text.gd` (`AbilityText`). Never hardcode numbers: use tokens `{e0.damage}`, `{e1.status.default_duration}`, `{area}`, `{search}`, `{cast}`, `{icd}`, `{recent}`, products `{a*b}`, formats `:pct :inv_pct :bonus_pct :abs`.
- Colour tags with icons: `[dmg] [heal] [shield] [cc] [buff] [debuff] [gold] [summon] [xp] [kw]`. Icons live in `graphics/ui/ability_icons/`.
- Do not write cooldown, range or radius in the text: the header (`AbilityText.stat_line`) shows them with icons. Write units glued to the token (`{e0.duration}s`, `{x:pct}%`); they become part of the number.
- Rendering: known level -> one number; upgrade preview (`compare_level`, used by the hero level-up card) -> "old -> new"; no level -> `200/400/600/800` in one style. `AbilityText.plain()` gives text without BBCode.
- Entry points: `AbilityText.tooltip/type_line/stat_line/render/plain`; `ContentButton.describe_ability_definition(ability, level)`; `AbilityDefinition.for_hero_level()` sets meta `hero_level`.
- Tooltips are now RichTextLabel (`ui/common/content_tooltip.tscn`, width 400); the theme defines RichTextLabel normal/bold fonts. The hero ability reward popup (`hero_ability_reward_popup.gd`) uses side-by-side cards (`_offer_card`).
- Several tests assert exact BBCode fragments (`test_management_ui`, `test_job_professionalism`, `test_priest_heal`, `test_despair_abilities`, `test_shieldbearer_job`); update them when changing the formatter.

### Known pre-existing test failures (not caused by these changes)
test_abilities (AI slot order), test_combat (anchor check with placeholder sprites), test_combat_results ("Post Battle panel shows Gold"), test_hero_ability_rewards, test_hero_selection, test_lust_abilities (base stats), test_stage13, test_stage14 (execution save), test_stage15, test_troll_priest (base stats). Several reflect intentional balance/content changes; update the tests rather than reverting content.
