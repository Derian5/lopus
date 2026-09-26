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
