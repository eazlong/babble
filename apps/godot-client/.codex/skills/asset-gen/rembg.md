# LinguaQuest Background Removal

Use this guide when a generated asset needs transparency before it enters the Godot project.

Applies to:

- Feifei frames and expression cutouts.
- NPC or player sprite frames.
- Props that layer over scene backgrounds.
- UI icons, badges, buttons, reward effects, and speech-bubble pieces.

Does not apply to:

- Full backgrounds and parallax layers.
- Tileable textures.
- Tripo3D source references; Tripo3D needs the solid background.

Never prompt for a "transparent background". Image generators often draw checkerboards or fake alpha. Prompt a solid matte background, then remove it.

## Background Color Strategy

Pick a solid prompt background that is distinct from the subject but sympathetic to the final scene:

| Target asset | Suggested solid background | Reason |
|---|---|---|
| Feifei / warm mascot sprite | muted teal or medium gray | separates from fur and glow while avoiding harsh green fringe |
| Forest prop or plant | steel blue or medium gray | separates from greens and browns |
| Mirage Inn object | desaturated blue gray | separates from warm wood, gold, and red accents |
| UI icon / badge | medium gray | neutral for edge inspection |
| Magic glow / star effect | dark blue gray | preserves light edges |

Prompt pattern:

```text
{subject}, {description}. Centered on a solid {bg_color} background, no shadow touching the frame edge.
```

Keep the subject centered with a margin. If corners do not show clean background color, regenerate before matting.

## CLI

Dependencies live in `.codex/skills/asset-gen/tools/requirements.txt`.

Install the project skill dependencies:

```bash
.venv/bin/python -m pip install -r .codex/skills/asset-gen/tools/requirements.txt
```

For an NVIDIA Linux workstation, GPU acceleration can be added separately with `onnxruntime-gpu` and the matching CUDA/cuDNN packages. The default project setup uses CPU-compatible `onnxruntime` so it works on macOS.

Single image:

```bash
python3 .codex/skills/asset-gen/tools/rembg_matting.py \
  tmp/asset-gen/feifei/reference.png \
  -o tmp/asset-gen/feifei/reference_cutout.png \
  --preview
```

Batch video frames:

```bash
python3 .codex/skills/asset-gen/tools/rembg_matting.py \
  --batch tmp/asset-gen/feifei/fly_raw/ \
  -o tmp/asset-gen/feifei/fly_clean/
```

Only move accepted final PNGs into `assets/...`. Keep raw frames and QA previews in `tmp/asset-gen/`.

## Modes

`-m auto` is the default and chooses a strategy from mask coverage:

| Mode | Auto when | Behavior |
|---|---|---|
| `trust` | 5-70% mask foreground | Keep mask foreground pixels, aggressively remove background |
| `adapt` | >70% mask foreground | Adaptive threshold; foreground pixels can be removed if background-colored |
| `color` | <5% mask foreground | Color matting only, rough fallback |

The tool reports `BG color`, `Mask: fg=... (%)`, and selected `Regime`.

Regenerate instead of tuning forever when:

- The background is not solid.
- The subject touches the image edge.
- Hair/fur/glow color is too close to the background.
- `Transparent: 0` appears.

## QA Verification

Always pass `--preview` for accepted cutouts. The preview writes a `_qa.png` showing the result on a contrasting color. Inspect that preview before moving the cutout into `assets/`.

Check:

- No checkerboard baked into the image.
- No obvious halo around Feifei, UI icons, stars, or glow effects.
- Important thin shapes, eyes, tails, hands, and badges survive.
- The final PNG has alpha transparency.
- The image still reads at its in-game display size.

## Fixing Results

- Background remnants: lower `--bg-thresh`, for example `--bg-thresh 0.03`.
- Missing foreground: use `-m trust`, or in adapt mode raise `--fg-thresh`, for example `--fg-thresh 0.30`.
- Colored fringe: try `-m adapt --fg-thresh 0.10`; if it persists, regenerate with a more distinct solid background.

Tune on one frame before applying flags to a whole batch.

## Acceptance

A cutout is accepted only when:

- The final PNG is in the correct `assets/...` path or ready to replace an existing frame.
- Raw and QA files remain in `tmp/asset-gen/` or are removed.
- The asset is listed in `docs/asset-manifest.md`.
- Godot import succeeds after the asset is moved.
