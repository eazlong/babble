# 启动先回蜃影客栈主人房，与腓腓交互后续行

- Status: accepted
- Date: 2026-09-14

## 背景

a5d2553 引入「场景 checkpoint + 启动 resume」：`BeginningFP._ready()` 一旦发现 `GameManager.current_scene` 指向其它场景，就立刻 `change_scene_to_file` 跳到存档点。玩家每次启动会直接落进上次的场景，跳过蜃影客栈主人房与腓腓，缺少「回到大本营再出发」的仪式感，也让存档点变成隐式跳转而不是玩家选择。

## 决定

保留自动读档（CLAUDE.md §10），但不自动跳转场景。启动恢复流程改为：

1. 主场景仍是 `BeginningFP`（蜃影客栈主人房）。
2. `GameManager.should_resume_to_scene("BeginningFP")` 只表示存在可继续的剧情存档点，且目标场景文件真实存在；它不再触发自动切换。
3. BeginningFP 进入 `_start_resume_room()`：腓腓主动在主人房发起对话并询问是否继续，玩家通过对话说出「出发 / Let's go / 继续」后，才切到 `GameManager.get_scene_path()` 指向的 `current_scene`。
4. 续行期间不调用 `set_checkpoint("BeginningFP")`，保证存档里的 `current_scene` 仍是玩家真正的剧情位置；若玩家在主人房再次退出，下次启动仍回到同一存档点。
5. 无存档、读档失败或存档点就是 `BeginningFP`（序章尚未完成）时，走原序章。

hub 的「语音出发」与启动续行都需要同一类口令，因此提取 `StoryContinueMarkers`，ASR candidate_answers 与本地匹配共用，避免两套白名单漂移。

## 后果

- 每次启动都会经过主人房与腓腓；这是刻意的产品仪式，不是多余的读档延迟。
- 序章中途退出仍只能从序章开头继续（当前存档没有序章阶段字段）；后续如需要，应单独存 prologue stage，而不是恢复隐式跳转。
- 启动续行只通过对话触发（与 hub 语音出发一致，共用 `AWAIT_RESUME_CONFIRM`）；不提供点击/触摸热区，也不新增可见的出发按钮；进入主人房由腓腓主动发起交互。

## 备选方案

- 维持启动直接 resume：缺少大本营交互，被否决。
- 每次启动重放完整序章：会重复取名与世界观，被否决。
- 用可见「继续」按钮或点击/触摸跳过对话：违背 commit 4c8d419 的语音方向与「只能通过对话触发」约束，被否决。
