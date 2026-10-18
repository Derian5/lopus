---
name: generate-game-art
description: Use when generating, editing, downloading, or integrating game art, sprites, ability icons, item icons, portraits, bosses, event illustrations, or other visual assets through Runware.
---

# Generate Game Art

Use the Runware MCP tools to create image assets for this Godot project. Treat generation as a paid external operation: never call a paid generation tool unless the user explicitly asks to generate or edit an image.

## Model Routing

Use only these models unless the user explicitly requests another model:

| Role | Model | AIR ID | Use |
| --- | --- | --- | --- |
| Cheap | FLUX.2 [klein] 9B | `runware:400@2` | Fast experiments, composition drafts, icon variants, simple items |
| Balanced | FLUX.2 [dev] | `runware:400@1` | Prototypes and non-commercial development assets |
| Quality | FLUX.2 [pro] | `bfl:5@1` | Final heroes, bosses, events, complex illustrations, demanding edits |

Selection rules:

- Default to Cheap for exploration and multiple variants.
- Use Balanced only for prototypes unless the user has independently confirmed that the FLUX.2 Dev license permits the intended commercial use. Runware describes this model as intended for non-commercial research and workflow prototyping.
- Use Quality for publication-ready commercial assets or when the user explicitly asks for maximum quality.
- If the user names Cheap, Balanced, Quality, Klein, Dev, or Pro, use the corresponding AIR ID exactly.
- Do not silently substitute a different model. If a selected model is unavailable, explain that and ask before changing it.

## Before Generation

1. Inspect the relevant game definitions, existing graphics, and UI context before writing the prompt.
2. Use Runware `model_schema` for the selected AIR ID before its first call in a session. Send only fields supported by the current schema.
3. Use `model_pricing` before the first paid call in a session or whenever dimensions, result count, or model changes materially.
4. State the selected model, output dimensions, result count, and estimated total cost before calling `run`.
5. An explicit image-generation request authorizes up to four Cheap outputs or one Balanced output when the expected total is at most USD 0.05.
6. Ask for confirmation before using Quality unless the user explicitly requested Quality/Pro, before spending more than USD 0.05 in one operation, or before generating more than four images.
7. Never start a batch for every ability, character, or item from a general discussion. Require explicit batch approval.

## Project Art Direction

Unless the user supplies different art direction, preserve this shared style:

- Hand-painted dark fantasy with a slightly rough inked texture.
- Gothic medieval atmosphere, ominous but readable.
- Strong silhouettes, restrained detail, dramatic chiaroscuro, deep charcoal shadows, and one dominant magical accent color.
- Important forms must remain readable at their final in-game size.
- No photorealism, glossy 3D-render look, anime styling, modern objects, text, letters, numbers, watermark, signature, or baked-in UI frame.
- Keep important details away from the outer 10 percent of the canvas.
- Match established project art when reference images are available; use reference images through the model's supported input fields rather than relying only on prose.

For ability and item icons:

- Generate square `1024x1024` PNG source art unless the model schema or user requires otherwise.
- Center one dominant symbol or action in a compact circular composition.
- Use a simple dark background with high subject separation.
- Avoid tiny faces, thin lines, busy scenery, and details that disappear at 64 pixels.

For character sprites or sheets:

- Confirm view angle, frame layout, frame count, animation names, background treatment, and target frame dimensions before generating.
- Do not claim that a single generated sheet is animation-ready without checking cell alignment, silhouette continuity, and frame-to-frame consistency.

## Runware Request

- Use `taskType: imageInference`, the selected AIR ID, `includeCost: true`, and `outputFormat: PNG` when supported.
- Prefer synchronous delivery for still images.
- Preserve the returned `seed`, `taskUUID`, model AIR ID, prompt, dimensions, and reported cost in the response summary.
- For variants of one concept, preserve the prompt and vary seeds. For refinements, use supported reference-image or editing inputs and keep the chosen source as a reference.
- Do not assume `negativePrompt`, `steps`, `CFGScale`, transparency, or other parameters exist. Read the model schema first.

## Review And Download

1. For exploratory work, show generated candidates and wait for the user's selection before integrating one into gameplay content.
2. If the user explicitly asks for automatic selection, choose the candidate with the clearest silhouette and best readability at target size.
3. Download accepted source images into `graphics/generated/runware/source/` using a stable ASCII filename based on the content ID, for example `ability_wrath_frenzy_source.png`.
4. Put processed, game-ready images in the appropriate existing graphics directory. If no suitable directory exists, use `graphics/generated/runware/final/`.
5. Never overwrite an existing asset unless the user explicitly approves replacement. Add `_v2`, `_v3`, or a descriptive suffix instead.
6. Keep source images separate from resized or cropped final assets.
7. Use a terminal download command for binary image URLs. Verify that the downloaded file exists and has a non-zero size before editing content references.

## Godot Integration

1. Inspect the relevant Resource schema and nearby `.tres` examples before assigning an asset.
2. Prefer data-driven references such as `icon` or `presentation_icon`; do not hardcode content IDs into combat logic.
3. Use project-relative `res://` paths.
4. Import new assets with one headless Godot editor refresh before testing them.
5. Report every generated file, content definition changed, model used, seed, and actual reported cost.
6. Do not commit generated assets unless the user explicitly requests a commit.

## Failure Handling

- On insufficient balance, authentication failure, invalid schema, or model unavailability, stop and report the exact error. Do not retry paid calls repeatedly.
- If a result is poor, do not spend again automatically unless the original request clearly authorized multiple variants.
- If OAuth is not connected, instruct the user to complete the official `mcp.runware.ai` browser flow. Never ask the user to paste an API key into chat or save it in the repository.
