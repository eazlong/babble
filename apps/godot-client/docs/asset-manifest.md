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
| Mirage Inn hall background | P0 fullscreen hall view for MirageInnIntroduction, showing left, center, and right room entrances | `assets/textures/backgrounds/mirage_inn_hall_bg.png` | 1920x1080 fullscreen | Wanxiang `wanx` via asset-gen | provider billing | Warm oriental fantasy inn hall, three readable room entrances, clean safe composition, no UI baked in | imported | Dimension/mode verified; Godot import completed; editor layout still reports unrelated `MainMenuController.gd` parse errors |
| Mirage Inn formation room background | P0 fullscreen formation room background with clean center area for artifact seats | `assets/textures/backgrounds/mirage_inn_formation_room_bg.png` | 1920x1080 fullscreen | Wanxiang `wanx` via asset-gen | provider billing | Quiet purple-gray formation chamber, six-seat composition context, small golden hope light, child-safe mood | imported | Dimension/mode verified; Godot import completed; editor layout still reports unrelated `MainMenuController.gd` parse errors |
| Mirage Inn player room background | P0 fullscreen player room background with bookshelf and wardrobe layout | `assets/textures/backgrounds/mirage_inn_player_room_bg.png` | 1920x1080 fullscreen | Wanxiang `wanx` via asset-gen | provider billing | Warm player room, bookshelf emphasized, wardrobe on the right, calm personal base feeling | imported | Dimension/mode verified; Godot import completed; editor layout still reports unrelated `MainMenuController.gd` parse errors |
| Word spirit library background | P0 fullscreen independent word-spirit library space | `assets/textures/backgrounds/word_spirit_library_bg.png` | 1920x1080 fullscreen | Wanxiang `wanx` via asset-gen | provider billing | Teal magical library, floating pages and soft boundaries, no heavy baked instructional text | imported | Dimension/mode verified; Godot import completed; editor layout still reports unrelated `MainMenuController.gd` parse errors |
| Mirage Inn guest room background | P0 fullscreen guest-room preview background | `assets/textures/backgrounds/mirage_inn_guest_room_bg.png` | 1920x1080 fullscreen | Wanxiang `wanx` via asset-gen | provider billing | Quiet guest room door with distant inviting light, future guest hint without horror mood | imported | Dimension/mode verified; Godot import completed; editor layout still reports unrelated `MainMenuController.gd` parse errors |
| Empty artifact seat | P0 alpha prop for six empty artifact positions in the formation room | `assets/textures/objects/inn/artifact_seat_empty.png` | 128x128 px | Wanxiang `wanx` via asset-gen, matte cutout | provider billing | Small golden stone artifact pedestal, empty but hopeful, readable silhouette on alpha | imported | Dimension/mode/alpha verified; Godot import completed; editor layout still reports unrelated `MainMenuController.gd` parse errors |
| First artifact light | P0 alpha prop for first artifact clue, suitable for breathing glow animation | `assets/textures/objects/inn/artifact_first_light.png` | 96x96 px | Wanxiang `wanx` via asset-gen, matte cutout | provider billing | Small golden magical light point, soft child-friendly glow, centered cutout | imported | Dimension/mode/alpha verified; Godot import completed; editor layout still reports unrelated `MainMenuController.gd` parse errors |
| Closed magic bookshelf | P0 alpha prop for player room bookshelf default state | `assets/textures/objects/inn/bookshelf_closed.png` | 420x520 px | Wanxiang `wanx` via asset-gen, matte cutout | provider billing | Warm wooden bookshelf with subtle magical seams, closed state, no button-like styling | imported | Dimension/mode/alpha verified; Godot import completed; editor layout still reports unrelated `MainMenuController.gd` parse errors |
| Awake magic bookshelf | P0 alpha prop for bookshelf voice wake state | `assets/textures/objects/inn/bookshelf_awake.png` | 420x520 px | Wanxiang `wanx` via asset-gen, matte cutout | provider billing | Same-style bookshelf with clearer teal-gold glow from book gaps after voice prompt | imported | Dimension/mode/alpha verified; Godot import completed; editor layout still reports unrelated `MainMenuController.gd` parse errors |
| Empty wardrobe reward slots | P0 alpha prop for wardrobe preview and empty reward positions | `assets/textures/objects/inn/wardrobe_empty.png` | 360x460 px | Wanxiang `wanx` via asset-gen, matte cutout | provider billing | Warm wardrobe with visible empty reward slots, restrained first-visit preview | imported | Dimension/mode/alpha verified; Godot import completed; editor layout still reports unrelated `MainMenuController.gd` parse errors |
| Hello word spirit | P0 alpha prop for first word spirit used in hello teaching flow | `assets/textures/objects/inn/word_spirit_hello.png` | 256x256 px | Wanxiang `wanx` via asset-gen, matte cutout | provider billing | Cute glowing first word spirit with hello-related visual, teal mint glow, readable at small size | imported | Dimension/mode/alpha verified; Godot import completed; editor layout still reports unrelated `MainMenuController.gd` parse errors |
| Guest room distant light | P0 alpha prop for distant guest-room voice and light preview | `assets/textures/objects/inn/guest_room_distant_light.png` | 420x520 px | Wanxiang `wanx` via asset-gen, matte cutout | provider billing | Doorway light and soft voice-like glow, inviting future guest signal without scare tone | imported | Dimension/mode/alpha verified; Godot import completed; editor layout still reports unrelated `MainMenuController.gd` parse errors |
| Beginning fog sky | P0 foggy sky and mist layer for BeginningFP | `assets/textures/backgrounds/fog.png` | 1920x1080 px | Existing local generated PNG | none in this pass | Low-contrast cyan-gray awakening mist for first-person prologue | scene-verified | Dimensions verified with `sips`; wired in `BeginningFP.tscn`; Godot import/load checked |
| Beginning far tree line | P0 replacement for hotel grass placeholder | `assets/textures/backgrounds/beginning_trees_far.png` | 1920x800 px | Existing local generated PNG | none in this pass | Distant soft forest silhouette, bottom-weighted alpha layer | scene-verified | Dimensions verified with `sips`; `BeginningFP.tscn` no longer references `assets/textures/hotel/grass.png`; Godot import/load checked |
| Beginning mid tree line | P0 replacement for hotel level placeholder | `assets/textures/backgrounds/beginning_trees_mid.png` | 1920x900 px | Existing local generated PNG | none in this pass | Midground mist forest layer for parallax reveal | scene-verified | Dimensions verified with `sips`; `BeginningFP.tscn` no longer references `assets/textures/hotel/level0.png`; Godot import/load checked |
| Beginning ground | P0 ground layer for BeginningFP | `assets/textures/backgrounds/forest_ground.png` | 1920x380 px | Existing local generated PNG | none in this pass | Re-exported readable grass/ground strip for y=936 scaled parallax layer | scene-verified | Dimensions verified with `sips`; wired in `BeginningFP.tscn`; Godot import/load checked |
| Feifei unified SpriteFrames | P0 unified companion animation resource | `assets/sprites/feifei/feifei_frames.tres` | SpriteFrames resource | Local resource assembly from existing Feifei PNG frames | none | Combines `default`, `idle`, `hint`, and `happy` animations for BeginningFP shoulder companion | scene-verified | Added resource and wired `FeifeiSprite` to it; Godot import/load checked |
| Beginning Feifei bubble | P0 shoulder dialogue bubble | `assets/textures/ui/fp/ui_feifei_bubble_fp.png` | 200x100 px | Existing local generated PNG | none in this pass | Pale yellow rounded Feifei bubble with gold border and right-lower tail | scene-verified | Dimensions verified with `sips`; `BubblePanel` uses TextureRect in `BeginningFP.tscn`; Godot import/load checked |
| Beginning mist continents | P0 distant six-continent reveal | `assets/textures/backgrounds/beginning_mist_continents.png` | 1320x220 px | Existing local generated PNG | none in this pass | Six distant continent silhouettes embedded in semi-transparent mist | scene-verified | Dimensions verified with `sips`; runtime reveal now uses Sprite2D texture instead of temporary polygons; Godot import/load checked |
| Beginning Mirage Inn ruins | P0 distant inn reveal prop | `assets/textures/objects/beginning_mirage_inn_ruins.png` | 300x190 px | Existing local generated PNG | none in this pass | Ruined Mirage Inn / formation entrance silhouette with readable Chinese sign | scene-verified | Dimensions verified with `sips`; runtime reveal now uses Sprite2D texture instead of procedural shapes; Godot import/load checked |
| Beginning star bar background | P0 top HUD star bar frame | `assets/textures/ui/fp/ui_starbar_bg.png` | 400x40 px | Existing local generated PNG | none in this pass | Deep-blue translucent rounded bar with gold border | scene-verified | Dimensions verified with `sips`; wired as `TextureRect` in `BeginningFP.tscn`; Godot import/load checked |
| Beginning star bar fill | P0 top HUD star bar fill | `assets/textures/ui/fp/ui_starbar_fill.png` | 380x30 px | Existing local generated PNG | none in this pass | Orange-gold to magic-gold fill with light surface gloss | scene-verified | Dimensions verified with `sips`; wired as `TextureRect` in `BeginningFP.tscn`; Godot import/load checked |
| Beginning quest tracker panel | UI panel for prologue task text | `assets/textures/ui/fp/ui_quest_tracker_bg.png` | 250x120 px | Existing local generated PNG | none in this pass | Deep-blue translucent quest tracker with light blue border | scene-verified | Dimensions verified with `sips`; wired as `TextureRect` in `BeginningFP.tscn`; Godot import/load checked |
| Beginning mic buttons | UI voice interaction states | `assets/textures/ui/fp/ui_mic_button_idle.png`, `assets/textures/ui/fp/ui_mic_button_recording.png` | 80x80 px each | Existing local generated PNG | none in this pass | Child-safe tactile microphone button idle and recording states | scene-verified | Wired in `BeginningFP.tscn`; controller swaps idle/recording textures on voice state; Godot import/load checked |
| Beginning compass | UI magic compass and arrow | `assets/textures/ui/fp/ui_compass_bg.png`, `assets/textures/ui/fp/ui_compass_arrow.png` | 100x100 px bg, 60x60 px arrow | Existing local generated PNG | none in this pass | Magical compass face with separate red-gold arrow overlay | scene-verified | Dimensions verified with `sips`; wired in `BeginningFP.tscn`; Godot import/load checked |
| Beginning completion badge | UI prologue completion badge | `assets/textures/ui/badge_beginning.png` | 150x150 px | Existing local generated PNG | none in this pass | Prologue completion badge without baked localization text | scene-verified | Dimensions verified with `sips`; `BadgeIcon` now uses TextureRect in `BeginningFP.tscn`; Godot import/load checked |

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
