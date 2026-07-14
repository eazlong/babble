# LinguaQuest Asset Generation Workflow

This document explains how to use the project-local `$asset-gen` skill to create suitable game resources for the Godot client.

Use this workflow for generated backgrounds, Feifei sprites, UI states, props, reward effects, and approved GLB prototypes.

## 1. Start From A Game Need

Define the asset in project terms before generating:

- Scene or feature: `BeginningFP`, `MirageInnIntroduction`, `SpiritForest`, `ChangAnMarket`, `RainbowGarden`, `SpellLibrary`, HUD, reward, review task.
- Runtime path under `assets/...`.
- In-game size or display behavior.
- Whether it replaces an existing file or adds a new resource.
- Required verification scene.

Record the planned row in [asset-manifest.md](/Users/gongzuoyonghu/Documents/code/games/lauguage_game/apps/godot-client/docs/asset-manifest.md).

## 2. Use The Local Skill

Invoke:

```text
$asset-gen
```

The skill lives at:

```text
.codex/skills/asset-gen/
```

Tool commands run from the Godot client root. Example image generation command:

```bash
.venv/bin/python .codex/skills/asset-gen/tools/asset_gen.py image \
  --model wanx \
  --aspect-ratio 1:1 \
  --prompt "Feifei, cute AI companion for a Chinese mythic children's RPG, readable 2D game sprite, centered on a solid muted teal background" \
  -o tmp/asset-gen/feifei/reference.png
```

## 3. Get Cost Approval

Before a paid batch, list:

- Target assets and paths.
- Model choices.
- Estimated total cost.
- Prompt summaries.
- Verification commands and scenes.

Do not run paid API calls until the user approves.

Required API keys depend on the output:

- `GOOGLE_API_KEY` for Gemini image generation.
- `XAI_API_KEY` for Grok image/video generation.
- `DASHSCOPE_API_KEY` for Tongyi Wanxiang image/video generation.
- `TRIPO3D_API_KEY` for GLB, rig, and retarget generation.

Domestic-provider examples:

```bash
export DASHSCOPE_API_KEY="..."
.venv/bin/python .codex/skills/asset-gen/tools/asset_gen.py image \
  --model wanx \
  --aspect-ratio 16:9 \
  --prompt "Mirage Inn background for a Chinese mythic children's RPG, warm readable first-person scene, no text" \
  -o tmp/asset-gen/backgrounds/mirage_inn.png

.venv/bin/python .codex/skills/asset-gen/tools/asset_gen.py video \
  --model wanx \
  --duration 5 \
  --resolution 720p \
  --prompt "Feifei gently hovering and waving, cute short idle loop, Chinese mythic children's RPG style" \
  -o tmp/asset-gen/feifei/fly.mp4
```

Current Wanxiang support in this CLI is text-to-image and text-to-video. Use Gemini for image-to-image reference edits until Wanxiang image editing is added.

## 4. Keep Working Files Out Of Runtime Paths

Use `tmp/asset-gen/` for:

- Reference images.
- Prompt experiments.
- Raw videos.
- Extracted raw frames.
- QA previews.
- Rejected files.

Move only accepted final assets into `assets/...`.

Common target paths:

| Asset | Target Path |
|---|---|
| Feifei frames | `assets/sprites/feifei/`, `assets/resources/sprites/feifei/` |
| Scene backgrounds | `assets/textures/backgrounds/`, `assets/textures/hotel/` |
| Inn props | `assets/textures/objects/inn/` |
| General props | `assets/textures/objects/` |
| UI | `assets/textures/ui/`, `assets/textures/ui/fp/` |
| Effects | `assets/textures/effects/`, `assets/textures/particles/` |

## 5. Match LinguaQuest Direction

Prompts must follow the current project direction:

- Chinese myth / Shanhaijing-inspired fantasy.
- Feifei as the companion; no Spark / old blue-bird direction.
- Child-friendly RPG adventure, not school-dashboard UI.
- Clear silhouettes and readable shapes at in-game size.
- Voice interaction should feel tactile, safe, and magical.

Avoid:

- Western magic academy motifs.
- Generic stock-game fantasy.
- Fake transparent backgrounds.
- Over-detailed sprites that collapse below 128 px.

## 6. Cutouts And Animated Sprites

For sprites, props, icons, and UI cutouts:

1. Generate on a solid matte background.
2. Read `.codex/skills/asset-gen/rembg.md`.
3. Run `rembg_matting.py` with `--preview`.
4. Inspect the QA preview.
5. Move only the accepted final PNG into `assets/...`.

Animated sprite pipeline:

```bash
ffmpeg -i tmp/asset-gen/feifei/fly.mp4 -vsync 0 tmp/asset-gen/feifei/fly_raw/%04d.png
python3 .codex/skills/asset-gen/tools/find_loop_frame.py tmp/asset-gen/feifei/fly_raw/
python3 .codex/skills/asset-gen/tools/rembg_matting.py \
  --batch tmp/asset-gen/feifei/fly_raw/ \
  -o tmp/asset-gen/feifei/fly_clean/
```

Then resize, rename, and wire the accepted frames into the relevant `.tres`.

## 7. Godot Verification

After moving files into `assets/...`, run:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit
```

For visible assets, inspect the scene that uses them. Key scenes:

- `assets/scenes/BeginningFP.tscn`
- `assets/scenes/MirageInnIntroduction.tscn`
- `assets/scenes/SpiritForest.tscn`
- `assets/scenes/ChangAnMarket.tscn`
- `assets/scenes/RainbowGarden.tscn`
- `assets/scenes/SpellLibrary.tscn`

Update [asset-manifest.md](/Users/gongzuoyonghu/Documents/code/games/lauguage_game/apps/godot-client/docs/asset-manifest.md) with import status and verification evidence.

## 8. GLB Guardrails

Use GLB only when a 3D asset is genuinely needed.

Rules:

- Keep GLB working references in `tmp/asset-gen/glb/` until accepted.
- Put accepted runtime GLB files under an approved `assets/models/...` path.
- Do not use mesh-generated trimesh or convex collision for gameplay collision; use primitive collision from AABB.
- Do not put `.gdignore` under `assets/`.
- If Tripo3D times out, resume from the sidecar instead of resubmitting.

## Done Definition

A generated asset is done only when:

- The accepted file is under the intended `assets/...` path.
- It has a row in `docs/asset-manifest.md`.
- Godot import succeeds.
- The owning scene/resource reference is checked.
- Temporary files are kept out of runtime paths.
