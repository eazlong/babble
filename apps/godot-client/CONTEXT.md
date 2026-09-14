# Godot Client

This context defines the domain language used by the Godot client for scene-driven learning flows and dialogue playback.

## Language

**Dialogue Flow**:
A continuous linear dialogue segment with no special animation, input wait, reward grant, or scene transition inside it. A scene controller may play multiple dialogue flows and coordinate non-dialogue actions between them.
_Avoid_: Complete scene flow, step, animation block

**Dialogue Flow Config**:
A JSON file that defines one or more dialogue flows by `flow_id`, speaker, localized lines, and parameter placeholders. Dialogue flow configs live separately from scene configs because dialogue content changes independently from scene metadata and resource loading.
_Avoid_: Scene config, script constants, hard-coded dialogue table

**Scene Dialogue Flow File**:
A dialogue flow config scoped to one scene and containing all dialogue flows for that scene. Each flow still has a globally unique `flow_id` so the loader can index flows across files.
_Avoid_: One file per line, one file per dialogue flow

**Dialogue Flow Loader**:
A pure data component that loads, validates, queries, localizes, and parameterizes dialogue flows. It does not play UI, synthesize speech, wait for audio, or advance scene state.
_Avoid_: Dialogue player, scene controller, TTS handler

**Local Dialogue Flow Loader**:
A dialogue flow loader instantiated by a scene controller instead of registered as an autoload singleton. The local loader avoids new global state while dialogue flow loading remains a pure data concern.
_Avoid_: Dialogue flow singleton, global dialogue registry

**Named Placeholder**:
A `{name}` token inside localized dialogue text that is replaced by a runtime value before playback. Named placeholders are preferred over positional `%s` formatting because localized languages may need different word order or repeated values.
_Avoid_: Positional placeholder, `%s`

**Dialogue Language Fallback**:
The runtime rule used when a dialogue line does not contain the requested language: requested language first, then `en`, then any available language with a warning. Fallback happens when localized lines are requested, not when JSON files are loaded.
_Avoid_: Load-time translation, silent empty text

**Dialogue Flow Load Error**:
A recoverable problem in a dialogue flow config that should be reported during loading or lookup without crashing the scene. Invalid files fail as files, invalid flows or lines are skipped, duplicate `flow_id` values are rejected, and missing runtime placeholders remain visible with a warning.
_Avoid_: Silent correction, scene crash

## Story and Scene Language

**蜃影客栈（Mirage Inn）**:
玩家的大本营与无雾安全区；在序章开场时已主动认玩家为主人，但阵法、升级与客源仍要靠找回六神器逐步恢复。
_Avoid_: 客栈遗址、破旧茶棚（作为当前正典）

**认主（Inn Recognition）**:
腓腓把玩家从混沌迷雾救回客栈时发生的故事事件：客栈大门与主人房自行打开、阵法第一点光回应，客栈主动承认玩家为主人。认主只确定归属，不代表客栈已恢复。
_Avoid_: 绑定、解锁

**绑定（Binding）**:
客户端系统层的 hub 解锁含义，指 unlocked_areas、checkpoint、MirageInnHub 等实现状态；不用于向玩家描述故事事件。
_Avoid_: 认主、导览

**大本营导览（Base Tour）**:
序章第三幕的内容：从主人房接续醒来，依次认识主人房（书柜 → 词灵书阁 → 衣橱）、大厅、阵法房间、客房，最后回大厅总结；不再包含“走进客栈”的演出。
_Avoid_: 进客栈、大本营绑定

**语音出发（Voice Departure）**:
蜃影客栈 hub 复访时，玩家不与按钮交互；玩家对腓腓说出出发意图（Let's go / 出发 / 下一课），腓腓确认后场景切到下一课。场景中不得出现可点击的出发按钮。
_Avoid_: 出发按钮、下一课按钮

**主人房（Owner's Room / 自己的房间）**:
玩家在蜃影客栈的私人房间，也是序章醒来的地方；内有书架（通往词灵书阁）和衣橱（外观奖励）。BeginningFP 与 MirageInnIntroduction 共用 `mirage_inn_owner_room_bg.png` 作为基准背景。
_Avoid_: 玩家房间（旧美术文档用词）、客房

**客房（Guest Room）**:
蜃影客栈接待远方旅客的房间；在导览最后一站作为未来客源与会话练习的预告，不是玩家醒来的房间。
_Avoid_: 主人房

**阵法房间（Formation Room）**:
装有六件神器空位与阵法的房间，是主线推进核心；神器遗失后阵法正在变弱。
_Avoid_: 魔法阵房

**魔法投影（Magic Projection）**:
腓腓在主人房床前展示迷雾岛与六道光的剧情演出，用于替代客栈外景世界观揭示；复用 `beginning_mist_continents.png`。
_Avoid_: 天窗、窗外实景
