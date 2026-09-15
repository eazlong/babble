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

> 2026-09-14 正典变更：序章改为蜃影客栈主人房开场。以下 Beginning 户外资产退出 BeginningFP（文件保留，不再被场景引用）：fog sky / far tree line / mid tree line / ground / Mirage Inn ruins。主人房基准背景统一为 `mirage_inn_owner_room_bg.png`（由 `assets/sprites/feifei/room_1.png` 迁移命名），并与 MirageInnIntroduction 共用；六道光资产改为室内魔法投影。
>
> 2026-09-15 架构变更：腓腓由逐帧 SpriteFrames（`feifei_frames.tres` + `FeifeiShoulder.gd` + `AnimatedSprite2D`）改为**骨骼动画**（`FeifeiBody.tscn`：Skeleton2D + Polygon2D 逐顶点蒙皮）。美术交付物从逐帧 PNG 序列变为单张分层部件图集 `feifei_part.png`。`ui_feifei_bubble_fp.png` 同时退役（气泡改为 `FeifeiBody.gd` 程序化绘制）。

| Name | Purpose | Target Path | In-game Size | Source | Cost | Prompt Summary | Status | Verification |
|---|---|---|---|---|---:|---|---|---|
| Feifei reference | Canonical companion style anchor for future Feifei work | `assets/sprites/feifei/feifei_reference.png` | 256x256 px display target | Godot render of existing `FeifeiBody.tscn` (RESET pose; per 2026-09-15 user instruction no re-design, derived from in-engine art) | none | — (rendered, not generated) | imported/accepted | 2026-09-15: headless Godot render → center-crop 256×256 RGBA; QA PASS; vision-verified complete pose (head/body/wings/tail) consistent with `feifei_part.png` atlas |
| Feifei glow | Warm radial glow sprite for Feifei companion highlights | `assets/sprites/feifei/feifei_glow.png` | 140x140 px | Pillow radial gradient (star-sand gold #FFE082) | none | — (synthesized) | imported/accepted | 2026-09-15: 140×140 RGBA radial falloff α≤200; QA PASS |
| Mirage Inn main background | Fullscreen background for inn introduction / review hub | `assets/textures/hotel/mirage_inn_main.png` | 1920x1080 fullscreen | planned Wanxiang `wanx2.1-t2i-turbo` | provider billing | Warm Shanhaijing-inspired mirage inn interior/exterior, readable first-person scene layers | planned | Pending generation and scene check |
| Inn review prop kit | Reusable management-game objects for review tasks | `assets/textures/objects/inn/` | 128-256 px props | planned Wanxiang kit sheet | provider billing | 2D prop kit with bowls, teapot, order slips, lantern tokens, solid background for cutout | planned | Pending generation, slicing, and manifest split rows |
| First-person mic button refresh | Voice interaction UI states | `assets/textures/ui/fp/ui_mic_button_idle.png`, `assets/textures/ui/fp/ui_mic_button_recording.png` | Existing UI frame size | planned Wanxiang or Gemini | provider billing | Child-safe tactile voice button, idle and recording states, LinguaQuest UI style | planned | Pending generation and HUD check |
| Mirage Inn hall background | P0 fullscreen hall view for MirageInnIntroduction, showing left, center, and right room entrances | `assets/textures/backgrounds/mirage_inn_hall_bg.png` | 1920x1080 fullscreen | Wanxiang `wanx` via asset-gen | provider billing | Warm oriental fantasy inn hall, three readable room entrances, clean safe composition, no UI baked in | imported | Dimension/mode verified; Godot import completed; editor layout still reports unrelated `MainMenuController.gd` parse errors |
| Mirage Inn formation room background | P0 fullscreen formation room background with clean center area for artifact seats | `assets/textures/backgrounds/mirage_inn_formation_room_bg.png` | 1920x1080 fullscreen | Wanxiang `wanx` via asset-gen | provider billing | Quiet purple-gray formation chamber, six-seat composition context, small golden hope light, child-safe mood | imported | Dimension/mode verified; Godot import completed; editor layout still reports unrelated `MainMenuController.gd` parse errors |
| Mirage Inn owner room background | P0 shared owner-room base background for BeginningFP prologue wake-up and MirageInnIntroduction first tour stop | `assets/textures/backgrounds/mirage_inn_owner_room_bg.png` | 1920x1080 fullscreen | migrate/rename local generated `assets/sprites/feifei/room_1.png` via asset-gen pipeline | none in this pass | Warm Mirage Inn owner room interior, subtle wooden cabinet/window/curtain/table readability, no bed in frame, child-friendly, matches inn art | imported/wired | Source image 2560x1600; target 1920x1080; both BeginningFP and MirageInnIntroduction preload the same file; BeginningFP.tscn wired via ExtResource("2_tov5l") |
| Word spirit library background | P0 fullscreen independent word-spirit library space | `assets/textures/backgrounds/word_spirit_library_bg.png` | 1920x1080 fullscreen | Wanxiang `wanx` via asset-gen | provider billing | Teal magical library, floating pages and soft boundaries, no heavy baked instructional text | imported | Dimension/mode verified; Godot import completed; editor layout still reports unrelated `MainMenuController.gd` parse errors |
| Mirage Inn guest room background | P0 fullscreen guest-room preview background | `assets/textures/backgrounds/mirage_inn_guest_room_bg.png` | 1920x1080 fullscreen | Wanxiang `wanx` via asset-gen | provider billing | Quiet guest room door with distant inviting light, future guest hint without horror mood | imported | Dimension/mode verified; Godot import completed; editor layout still reports unrelated `MainMenuController.gd` parse errors |
| Empty artifact seat | P0 alpha prop for six empty artifact positions in the formation room | `assets/textures/objects/inn/artifact_seat_empty.png` | 128x128 px | Wanxiang `wanx` via asset-gen, matte cutout | provider billing | Small golden stone artifact pedestal, empty but hopeful, readable silhouette on alpha | imported | Dimension/mode/alpha verified; Godot import completed; editor layout still reports unrelated `MainMenuController.gd` parse errors |
| First artifact light | P0 alpha prop for first artifact clue, suitable for breathing glow animation | `assets/textures/objects/inn/artifact_first_light.png` | 96x96 px | Wanxiang `wanx` via asset-gen, matte cutout | provider billing | Small golden magical light point, soft child-friendly glow, centered cutout | imported | Dimension/mode/alpha verified; Godot import completed; editor layout still reports unrelated `MainMenuController.gd` parse errors |
| Closed magic bookshelf | P0 alpha prop for player room bookshelf default state | `assets/textures/objects/inn/bookshelf_closed.png` | 420x520 px | Wanxiang `wanx` via asset-gen, matte cutout | provider billing | Warm wooden bookshelf with subtle magical seams, closed state, no button-like styling | imported | Dimension/mode/alpha verified; Godot import completed; editor layout still reports unrelated `MainMenuController.gd` parse errors |
| Awake magic bookshelf | P0 alpha prop for bookshelf voice wake state | `assets/textures/objects/inn/bookshelf_awake.png` | 420x520 px | Wanxiang `wanx` via asset-gen, matte cutout | provider billing | Same-style bookshelf with clearer teal-gold glow from book gaps after voice prompt | imported | Dimension/mode/alpha verified; Godot import completed; editor layout still reports unrelated `MainMenuController.gd` parse errors |
| Empty wardrobe reward slots | P0 alpha prop for wardrobe preview and empty reward positions | `assets/textures/objects/inn/wardrobe_empty.png` | 360x460 px | Wanxiang `wanx` via asset-gen, matte cutout | provider billing | Warm wardrobe with visible empty reward slots, restrained first-visit preview | imported | Dimension/mode/alpha verified; Godot import completed; editor layout still reports unrelated `MainMenuController.gd` parse errors |
| Hello word spirit | P0 alpha prop for first word spirit used in hello teaching flow | `assets/textures/objects/inn/word_spirit_hello.png` | 256x256 px | Wanxiang `wanx` via asset-gen, matte cutout | provider billing | Cute glowing first word spirit with hello-related visual, teal mint glow, readable at small size | imported | Dimension/mode/alpha verified; Godot import completed; editor layout still reports unrelated `MainMenuController.gd` parse errors |
| Guest room distant light | P0 alpha prop for distant guest-room voice and light preview | `assets/textures/objects/inn/guest_room_distant_light.png` | 420x520 px | Wanxiang `wanx` via asset-gen, matte cutout | provider billing | Doorway light and soft voice-like glow, inviting future guest signal without scare tone | imported | Dimension/mode/alpha verified; Godot import completed; editor layout still reports unrelated `MainMenuController.gd` parse errors |
| Beginning fog sky | P0 foggy sky and mist layer for BeginningFP | `assets/textures/backgrounds/fog.png` | 1920x1080 px | Existing local generated PNG | none in this pass | Low-contrast cyan-gray awakening mist for first-person prologue | retired from prologue; asset kept | No longer referenced by BeginningFP after canon change; keep file for archive/reuse |
| Beginning far tree line | P0 replacement for hotel grass placeholder | `assets/textures/backgrounds/beginning_trees_far.png` | 1920x800 px | Existing local generated PNG | none in this pass | Distant soft forest silhouette, bottom-weighted alpha layer | retired from prologue; asset kept | No longer referenced by BeginningFP after canon change; keep file for archive/reuse |
| Beginning mid tree line | P0 replacement for hotel level placeholder | `assets/textures/backgrounds/beginning_trees_mid.png` | 1920x900 px | Existing local generated PNG | none in this pass | Midground mist forest layer for parallax reveal | retired from prologue; asset kept | No longer referenced by BeginningFP after canon change; keep file for archive/reuse |
| Beginning ground | P0 ground layer for BeginningFP | `assets/textures/backgrounds/forest_ground.png` | 1920x380 px | Existing local generated PNG | none in this pass | Re-exported readable grass/ground strip for y=936 scaled parallax layer | retired from prologue; asset kept | No longer referenced by BeginningFP after canon change; keep file for archive/reuse |
| ~~Feifei unified SpriteFrames~~ | ~~P0 unified companion animation resource~~ | ~~`assets/sprites/feifei/feifei_frames.tres`~~ | — | — | none | — | **superseded** | ⚠️ **已废弃（2026-09-15）**：腓腓改为骨骼动画，本资源不再被 `BeginningFP` 引用；其 `CompressedTexture2D` 子资源本就为空（无 image data）。保留仅为历史记录 |
| Feifei skeletal body | P0 companion rebuilt as Skeleton2D + per-vertex polygon skinning (Spine-style), replacing frame-based SpriteFrames | `assets/scenes/components/FeifeiBody.tscn` + `assets/scripts/components/FeifeiBody.gd` | `BeginningFP` instance: `position (770, 704)`, `scale 0.6` | Skeleton2D + 14 skinned Polygon2D sampling `feifei_part.png` | none | Skeletal companion with 3 parallel drivers: `AnimationPlayer` (`RESET`/`fly`/`idle`), `FaceAnimationPlayer` (`talk_mouth`), `BlinkController` (Tween blink) | imported/wired | Wired into `BeginningFP.tscn` as the `FeifeiLayer` node. Other 5 scenes still reference the retired `FeifeiShoulder` + empty `feifei_frames.tres` and remain to be migrated. 2026-09-15 atlas QA: `feifei_part.png` PASS（2048×2048 RGBA，无黑边）→ **accepted** |
| ~~Beginning Feifei bubble~~ | ~~P0 shoulder dialogue bubble~~ | ~~`assets/textures/ui/fp/ui_feifei_bubble_fp.png`~~ | 200x100 px | Existing local generated PNG | none in this pass | — | **retired** | 🗑️ **已退役（2026-09-15）**：气泡改为 `FeifeiBody.gd` 程序化绘制（`Panel` + `StyleBoxFlat` + `Polygon2D` 尾巴）。全仓库已无任何引用 |
| Beginning mist continents | P0 in-room magic projection reveal in BeginningFP owner room | `assets/textures/backgrounds/beginning_mist_continents.png` | 1320x220 px | Existing local generated PNG | none in this pass | Six distant continent silhouettes embedded in semi-transparent mist, staged as Feifei's in-room magic projection rather than sky/outdoor view | scene-verified | Reused in-room at ~(960,350) as magic projection; no sky/outdoor layer |
| Beginning Mirage Inn ruins | P0 distant inn reveal prop | `assets/textures/objects/beginning_mirage_inn_ruins.png` | 300x190 px | Existing local generated PNG | none in this pass | Ruined Mirage Inn / formation entrance silhouette with readable Chinese sign | retired from prologue; asset kept | No longer referenced by BeginningFP after canon change; keep file for archive/reuse |
| Beginning star bar background | P0 top HUD star bar frame | `assets/textures/ui/fp/ui_starbar_bg.png` | 400x40 px | Existing local generated PNG | none in this pass | Deep-blue translucent rounded bar with gold border | scene-verified | Dimensions verified with `sips`; wired as `TextureRect` in `BeginningFP.tscn`; Godot import/load checked |
| Beginning star bar fill | P0 top HUD star bar fill | `assets/textures/ui/fp/ui_starbar_fill.png` | 380x30 px | Existing local generated PNG | none in this pass | Orange-gold to magic-gold fill with light surface gloss | scene-verified | Dimensions verified with `sips`; wired as `TextureRect` in `BeginningFP.tscn`; Godot import/load checked |
| Beginning quest tracker panel | UI panel for prologue task text | `assets/textures/ui/fp/ui_quest_tracker_bg.png` | 250x120 px | Existing local generated PNG | none in this pass | Deep-blue translucent quest tracker with light blue border | scene-verified | Dimensions verified with `sips`; wired as `TextureRect` in `BeginningFP.tscn`; Godot import/load checked |
| Beginning mic buttons | UI voice interaction states | `assets/textures/ui/fp/ui_mic_button_idle.png`, `assets/textures/ui/fp/ui_mic_button_recording.png` | 80x80 px each | Existing local generated PNG | none in this pass | Child-safe tactile microphone button idle and recording states | scene-verified | Wired in `BeginningFP.tscn`; controller swaps idle/recording textures on voice state; Godot import/load checked |
| Beginning compass | UI magic compass and arrow | `assets/textures/ui/fp/ui_compass_bg.png`, `assets/textures/ui/fp/ui_compass_arrow.png` | 100x100 px bg, 60x60 px arrow | Existing local generated PNG | none in this pass | Magical compass face with separate red-gold arrow overlay | scene-verified | Dimensions verified with `sips`; wired in `BeginningFP.tscn`; Godot import/load checked |
| Beginning completion badge | UI prologue completion badge | `assets/textures/ui/badge_beginning.png` | 150x150 px | Existing local generated PNG | none in this pass | Prologue completion badge without baked localization text | scene-verified | Dimensions verified with `sips`; `BadgeIcon` now uses TextureRect in `BeginningFP.tscn`; Godot import/load checked |
| Batch 1 SFX set | P0/P1 gameplay SFX (13): area_unlock, badge_unlock, bookshelf_awake, celebration, changan_bell_ring, changan_mist_surge, guest_distant_hello, library_enter, magic_sparkle, ui_spirit_stone_hint, ui_spirit_stone_listen, ui_spirit_stone_success, word_spirit_clear | `assets/audio/sfx/*.ogg` (13 files) | 0.4–2.4 s each | `tools/synth_sfx.py` synthesized (stdlib, no AIGC) | none | — (synth WAV → `oggenc -q 5`) | imported/scene-verified | 2026-09-15: duration test 13/13 pass; `AudioManager` registry `SFX_REGISTERED_13`; 6-scene headless smoke 0 errors |
| Batch 1 ambience set | P0 ambient beds: beginning 90 s / inn 90 s / formation room 45 s / Chang'an market 90 s (seamless loops) | `assets/audio/amb/{beginning_ambient,inn_ambient,formation_room_hum,changan_market_ambient}.ogg` | seamless loops | `tools/synth_sfx.py` ambience builders | none | — (synth → `oggenc -b 128`) | imported/scene-verified | 2026-09-15: ffprobe duration verified; wired via `AudioManager.play_ambient_named` in BeginningFP / MirageInn / ChangAnMarket / ArchiveHall controllers |
| Batch 1 BGM set | P0 scene BGM: Chang'an market 103 s (Tozan, CC0), archive hall 92 s (yd, CC0) | `assets/audio/bgm/{changan_market_bgm,archive_hall_bgm}.ogg` | 92–103 s | OpenGameArt CC0 (attribution in `assets/audio/CREDITS.md`) | CC0 | — (direct download, no re-encode) | imported/scene-verified | 2026-09-15: ffprobe verified; wired via `AudioManager.play_bgm_named` (inn uses `set_bgm_volume(0.3)` provisional); CREDITS.md committed |

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

`BeginningFP` 正典验证应确认主人房背景为 `mirage_inn_owner_room_bg.png`（已接线），且不再引用 fog / trees / ground / inn ruins。

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
