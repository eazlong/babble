---
name: asset-gen
display_name: LinguaQuest Asset Generator
short_description: Generate LinguaQuest-ready Godot images, sprites, UI art, GLB props, and animation frames
default_prompt: "Use $asset-gen to plan and generate Godot-ready visual assets for LinguaQuest RPG."
allow_implicit_invocation: true
description: |
  Generate and prepare visual assets for this Godot 4.6 GDScript project: PNG backgrounds, character sprites, UI art, GLB props, animated sprite frames, and background removal. Supports Gemini, xAI Grok, Tongyi Wanxiang/DashScope, and Tripo3D while preserving LinguaQuest paths, style, costs, and verification gates.
---

# LinguaQuest Asset Generator

Use this skill when LinguaQuest RPG needs generated visual assets. The upstream tools come from `godogen/asset-gen`, but this skill is adapted for this repository's Godot 4.6 GDScript client.

This is not a Godot plugin and does not change the engine stack. It only helps produce and prepare files that the existing scenes, SpriteFrames, UI scripts, and resources can load.

## Project Rules

- Run commands from the project root: `/Users/gongzuoyonghu/Documents/code/games/lauguage_game/apps/godot-client`.
- Tools live in `.codex/skills/asset-gen/tools/`.
- Runtime-loaded outputs must go under existing Godot resource paths:
  - `assets/textures/backgrounds/` for scene backgrounds and layered parallax pieces.
  - `assets/textures/objects/` and `assets/textures/objects/inn/` for props.
  - `assets/textures/hotel/` for Mirage Inn backgrounds and management-game assets.
  - `assets/sprites/feifei/`, `assets/resources/sprites/feifei/`, `assets/sprites/player/`, `assets/sprites/oakley/`, or another existing sprite folder for character frames.
  - `assets/textures/ui/` and `assets/textures/ui/fp/` for UI art.
  - `assets/resources/sprites/` or `assets/resources/vfx_presets/` only when the file is a Godot resource the game loads.
- Working files, prompts, references, extracted raw frames, failed generations, and QA previews go under `tmp/asset-gen/`. Do not put generation inputs in `assets/` unless the game loads them.
- Keep existing file names, dimensions, and `.tres` references when replacing placeholders. If a resource path changes, update the owning `.tscn`, `.tres`, or script in the same change.
- Update `docs/asset-manifest.md` for every accepted generated asset.

## Cost And Approval

These tools call paid APIs. Before the first paid generation in a batch, present:

- Asset list and target paths.
- Model choice and estimated cost.
- Prompt summaries.
- Verification plan.

Wait for explicit user approval before spending. Never call paid generation speculatively.

Cost reference:

| Output | Typical model | Approx cost | Use here |
|---|---:|---:|---|
| Texture/simple prop | Grok or Wanxiang | provider billing | rocks, flowers, inn objects, simple UI texture |
| Character/reference | Gemini 1K or Wanxiang | provider billing | Feifei, NPCs, player hand style anchor |
| Background | Grok, Gemini 2K, or Wanxiang | provider billing | Mirage Inn, fog forest, market layers |
| GLB prop | Gemini ref + Tripo3D | 37 cents+ | inspectable 3D inn or market object |
| Rigged biped with clips | Gemini + Tripo3D rig/retarget | about 92 cents | only after prototype approval |

If a Tripo3D `glb`, `rig`, or `retarget` job times out, do not resubmit. The task id is saved in the `.tripo.json` sidecar; resume instead:

```bash
python3 .codex/skills/asset-gen/tools/asset_gen.py resume -o assets/path/model.glb
```

## Visual Direction

Match the current PRD and docs:

- Chinese myth / Shanhaijing-inspired fantasy, not western magic academy.
- Child-friendly, readable silhouettes, warm but not beige-dominated, vivid accents, clean contrast.
- Feifei is the AI companion. Do not generate old Spark / blue-bird assets.
- Children's client should feel like an RPG adventure, not a learning analytics dashboard.
- Voice interaction objects should look tactile and safe for 6-13 year olds.

For prompt writing, include:

- Subject, use case, camera/angle, target dimensions or aspect ratio.
- Existing scene context: BeginningFP, Mirage Inn, SpiritForest, ChangAn Market, RainbowGarden, SpellLibrary.
- Style anchor: modern Chinese mythic children's RPG, painterly 2D game asset, clean silhouette, readable at target size.
- Background rule: use a solid matte background for cutouts; never ask for "transparent background".

## Images

Basic command:

```bash
.venv/bin/python .codex/skills/asset-gen/tools/asset_gen.py image \
  --model gemini \
  --aspect-ratio 1:1 \
  --prompt "full prompt" \
  -o tmp/asset-gen/feifei/reference.png
```

Tongyi Wanxiang / DashScope command:

```bash
export DASHSCOPE_API_KEY="..."
.venv/bin/python .codex/skills/asset-gen/tools/asset_gen.py image \
  --model wanx \
  --aspect-ratio 1:1 \
  --prompt "full prompt" \
  -o tmp/asset-gen/feifei/reference.png
```

Accepted runtime outputs should then be copied or processed into an `assets/...` path named for the resource the game will load.

Model guidance:

- Use Gemini for Feifei, NPCs, exact UI pieces, style anchors, and image-to-image variants.
- Use Grok for lower-risk backgrounds, textures, simple props, and kit sheets where exact instruction following is less critical.
- Use Wanxiang when domestic API access, Chinese prompt handling, or China-region billing/compliance is preferred. The current CLI supports Wanxiang text-to-image; use Gemini for image-to-image until Wanxiang image editing is wired.
- Review every PNG before GLB conversion or sprite extraction.

Small sprite guidance:

- AI image minimums are much larger than many in-game sprites. Avoid designing final display sizes below 128 px unless the shape is very bold.
- For small UI/object sets, generate a 2x2 or 3x3 kit sheet and slice it:

```bash
python3 .codex/skills/asset-gen/tools/grid_slice.py tmp/asset-gen/ui/kit.png \
  --grid 2x2 \
  --names "badge_beginning,badge_forest,mic_idle,mic_recording" \
  -o tmp/asset-gen/ui/sliced
```

## Background Removal

Read `.codex/skills/asset-gen/rembg.md` before cutting out sprites, props, icons, or UI pieces.

Key rules:

- Never prompt for transparent background. Prompt a solid color, then matte it out.
- Use a background color distinct from the subject but close enough to the in-game environment that any residual fringe blends.
- Always generate and inspect a QA preview before accepting a cutout.

Example:

```bash
python3 .codex/skills/asset-gen/tools/rembg_matting.py \
  tmp/asset-gen/feifei/reference.png \
  -o assets/sprites/feifei/feifei_reference.png \
  --preview
```

## Animated Sprites

Use this for Feifei, player feedback, badges, stars, reward effects, and inn-object reactions.

Workflow:

1. Generate one approved reference image for the character or object.
2. Generate pose frames using image-to-image; prompt only the action change.
3. Generate a short video from the pose when motion is needed. Grok uses the pose image as the starting frame; Wanxiang currently uses text-to-video in this CLI.
4. Extract frames with `ffmpeg`.
5. Trim loops with `find_loop_frame.py`.
6. Matte frames with `rembg_matting.py`.
7. Resize frames to match the existing SpriteFrames resource.
8. Update or create the `.tres` SpriteFrames resource and run Godot import.

Example extraction:

```bash
ffmpeg -i tmp/asset-gen/feifei/fly.mp4 -vsync 0 tmp/asset-gen/feifei/fly_raw/%04d.png
python3 .codex/skills/asset-gen/tools/find_loop_frame.py tmp/asset-gen/feifei/fly_raw/
python3 .codex/skills/asset-gen/tools/rembg_matting.py \
  --batch tmp/asset-gen/feifei/fly_raw/ \
  -o tmp/asset-gen/feifei/fly_clean/
```

Wanxiang text-to-video example:

```bash
export DASHSCOPE_API_KEY="..."
.venv/bin/python .codex/skills/asset-gen/tools/asset_gen.py video \
  --model wanx \
  --duration 5 \
  --resolution 720p \
  --prompt "Feifei gently hovering and waving in a Chinese mythic children's RPG style, seamless cute idle motion" \
  -o tmp/asset-gen/feifei/fly.mp4
```

Animation rules:

- Reuse one character reference for all actions.
- Keep chains no deeper than two image/video generations; identity drifts after that.
- Generate one direction and flip in Godot when possible. Direction prompts are unreliable.
- Source videos are usually around 24 fps; drive sprite playback around 1/24s unless the local `.tres` specifies otherwise.

## GLB Props And 3D Assets

Use GLB generation only when 3D adds real value. Most current LinguaQuest scenes are 2D/first-person layered scenes, so GLB is mainly for inspectable props, prototype 3D spaces, or future market/inn objects.

Commands:

```bash
python3 .codex/skills/asset-gen/tools/asset_gen.py glb \
  --image tmp/asset-gen/inn/teapot_ref.png \
  -o assets/models/inn/teapot.glb
```

GLB prompt/source rules:

- Use a 3/4 elevated view, centered single subject, solid white/gray background, matte finish.
- Do not remove the background before Tripo3D; it needs the solid background.
- For rigging, use biped humanoids only. Quadrupeds and mascot creatures should usually stay as 2D sprites unless a 3D prototype proves otherwise.

Godot import guardrails:

- After import, run Godot reimport.
- Use primitive collision shapes derived from AABB: Box, Sphere, Capsule. Do not generate trimesh or convex collision from imported meshes for gameplay collision.
- Do not place `.gdignore` under `assets/`.
- If writing generated `.tscn` scenes later, validate owner chains and do not recurse ownership into imported GLB or nested `.tscn` instances.

## Verification

After accepting generated assets into `assets/`, run the smallest relevant gate:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit
```

For scene-visible assets, also open or capture the relevant scene:

- `assets/scenes/BeginningFP.tscn`
- `assets/scenes/MirageInnIntroduction.tscn`
- `assets/scenes/SpiritForest.tscn`
- `assets/scenes/ChangAnMarket.tscn`
- `assets/scenes/RainbowGarden.tscn`
- `assets/scenes/SpellLibrary.tscn`

A generated asset is not done until:

- It is in the intended `assets/...` path.
- It is listed in `docs/asset-manifest.md`.
- Godot import succeeds.
- The relevant scene or resource reference is checked.
- Any temporary QA files that should not ship are left in `tmp/asset-gen/` or removed.

## Manifest Entry

For every accepted asset, update `docs/asset-manifest.md` with:

- Name.
- Purpose.
- Target path.
- In-game size or display dimensions.
- Source model and approximate cost.
- Prompt summary.
- Status: planned, generated, accepted, imported, scene-verified.
- Verification evidence.

Do not use generated assets in production scenes without a manifest row.
