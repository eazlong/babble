# LinguaQuest Asset Manifest

This manifest tracks generated visual assets accepted into the Godot client. Every AI-generated runtime asset must have a row before it is wired into production scenes.

Working files, references, failed generations, raw animation frames, and QA previews belong in `tmp/asset-gen/`. Runtime-loaded files belong in `assets/...`.

## Status Values

- `planned`: approved target, not generated yet.
- `generated`: generated but not accepted.
- `accepted`: visually approved, ready to move or process.
- `imported`: placed under `assets/...` and imported by Godot.
- `scene-verified`: visible in the intended scene/resource without missing references, scale errors, or obvious artifacts.
- `rejected`: not used; keep only if the rejected result explains an important decision.

## Cost Rules

Asset generation can call paid APIs. Before a paid batch starts, record the planned assets and estimated cost, then wait for explicit user approval.

If a Tripo3D job times out, resume from the `.tripo.json` sidecar instead of resubmitting.

## Generated Asset Table

| Name | Purpose | Target Path | In-game Size | Source | Cost | Prompt Summary | Status | Verification |
|---|---|---|---|---|---:|---|---|---|
| Feifei reference | Canonical companion style anchor for future Feifei frames | `assets/sprites/feifei/feifei_reference.png` | 256x256 px display target | planned Wanxiang `wanx2.1-t2i-turbo` | provider billing | Cute Feifei AI companion, Chinese mythic children's RPG style, centered solid matte background | planned | Pending generation and Godot import |
| Mirage Inn main background | Fullscreen background for inn introduction / review hub | `assets/textures/hotel/mirage_inn_main.png` | 1920x1080 fullscreen | planned Wanxiang `wanx2.1-t2i-turbo` | provider billing | Warm Shanhaijing-inspired mirage inn interior/exterior, readable first-person scene layers | planned | Pending generation and scene check |
| Inn review prop kit | Reusable management-game objects for review tasks | `assets/textures/objects/inn/` | 128-256 px props | planned Wanxiang kit sheet | provider billing | 2D prop kit with bowls, teapot, order slips, lantern tokens, solid background for cutout | planned | Pending generation, slicing, and manifest split rows |
| First-person mic button refresh | Voice interaction UI states | `assets/textures/ui/fp/ui_mic_button_idle.png`, `assets/textures/ui/fp/ui_mic_button_recording.png` | Existing UI frame size | planned Wanxiang or Gemini | provider billing | Child-safe tactile voice button, idle and recording states, LinguaQuest UI style | planned | Pending generation and HUD check |

## Required Verification Commands

Run after moving accepted generated files into `assets/...`:

```bash
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --import
/Applications/Godot.app/Contents/MacOS/Godot --headless --path . --quit
```

For scene-visible assets, also verify the relevant scene:

- `assets/scenes/BeginningFP.tscn`
- `assets/scenes/MirageInnIntroduction.tscn`
- `assets/scenes/SpiritForest.tscn`
- `assets/scenes/ChangAnMarket.tscn`
- `assets/scenes/RainbowGarden.tscn`
- `assets/scenes/SpellLibrary.tscn`

## Path Conventions

| Asset Type | Runtime Path | Working Path |
|---|---|---|
| Scene backgrounds | `assets/textures/backgrounds/`, `assets/textures/hotel/` | `tmp/asset-gen/backgrounds/` |
| Scene props | `assets/textures/objects/`, `assets/textures/objects/inn/` | `tmp/asset-gen/props/` |
| Feifei sprites | `assets/sprites/feifei/`, `assets/resources/sprites/feifei/` | `tmp/asset-gen/feifei/` |
| Player / NPC sprites | `assets/sprites/player/`, `assets/sprites/oakley/` | `tmp/asset-gen/characters/` |
| UI and effects | `assets/textures/ui/`, `assets/textures/ui/fp/`, `assets/textures/effects/` | `tmp/asset-gen/ui/`, `tmp/asset-gen/effects/` |
| GLB prototypes | `assets/models/...` only after import plan approval | `tmp/asset-gen/glb/` |

## Prompt Notes

Use the project direction from `docs/new/README.md` and `docs/rules.md`:

- Chinese myth / Shanhaijing-inspired RPG, not western magic school.
- Feifei is the companion; do not create old Spark / blue-bird assets.
- Child-facing visuals should support adventure, courage, voice interaction, and readable feedback.
- Avoid learning-dashboard imagery in child-facing assets.
