# 本地 ComfyUI + Qwen-Image 2.1 作为 asset-gen 的免费出图后端

- Status: accepted
- Date: 2026-09-22
- Scope: apps/godot-client

## Background

> /grill-with-docs 问：asset-gen 是否能使用本地部署的 qwen-image-2.1？

核验到的现状：

1. **付费通路当时是断的。** `asset_gen.py` 的 image 后端只有三种：Gemini SDK、
   xAI Grok SDK、DashScope 异步任务协议（`POST {base}/services/aigc/text2image/image-synthesis`
   → 轮询 `GET {base}/tasks/{id}` → 从 `output.results[].url` 下载）。三者都要付费 key，
   且技能文档要求首次生成前先报预算。环境里 `DASHSCOPE_API_KEY` / `GEMINI_*` / `XAI_*` / `TRIPO*`
   一个都没设，`apps/godot-client/` 下没有 `.env`，根 `.env` 只有 Supabase 三项。
2. **本地算力在旁边那台机器上。** nv241 跑 ComfyUI 0.30.0（798 节点），Qwen-Image 2.1 全套齐：
   `qwen_image_2.1_Q6_K.gguf`（走 `UnetLoaderGGUF`，唯一选项）、
   `qwen_image_2.1_vae_bf16.safetensors`、
   `qwen3vl_8b_int8_convrot.safetensors`（`CLIPLoader` type = `qwen_image`）。
3. **协议完全不同。** ComfyUI 说的是 `POST /prompt` + `GET /history/{prompt_id}` + `GET /view`，
   与 DashScope 的异步任务协议没有交集；`_download_url()` 只做 `requests.get(url)`，
   而 OpenAI 兼容服务返回的是 `b64_json`，直接指过去两头都不通。
4. **入口不稳定。** README 写的 `Public 24181 → ComfyUI 8081` 实测被腾讯 DNSPod 拦
   （302 到 `dnspod.qcloud.com/static/webblock.html`）；用户给的 `http://1.14.203.171/`
   （80 端口）实测 502；真正可用的是 `http://1.14.203.171:24181/`（HTTP 200）。
   备用通路是 SSH 隧道 `ssh -N -L 18081:127.0.0.1:8081 -p 24122 netgpu@wgma.bbxyard.com`（实测可用）。
5. **代价是慢。** 日志实测 1024px / 25 步 ≈ **482 秒**（约 16.3 s/it）且 lowvram 卸载
   （"2619.48 MB usable … 3386.25 MB offloaded"）；512px / 25 步约 **30 秒**。

## Decision

1. **新增 `comfy` 后端**作为 asset-gen 的第 4 个 image 后端（`--model comfy`），
   协议层独立成 `.codex/skills/asset-gen/tools/comfy_client.py`，不塞进 `asset_gen.py`。
2. **不写 DashScope 协议 shim。** shim 能换来"asset-gen 零改动"，代价是长期多一个
   必须有人守着启动的常驻进程；一段随脚本跑的客户端代码更便宜。
3. **连接信息全部走环境变量**，带默认值：`COMFY_URL`（默认 `http://1.14.203.171:24181`）、
   `COMFY_UNET` / `COMFY_CLIP` / `COMFY_VAE`（默认 Background 第 2 条的三个文件名）。
   不把 IP 写死在代码里——它已经变过一轮了。
4. **生成参数取 Qwen-Image 2.1 官方路径**：cfg `1.0`、`euler`、`simple`、25 步起；
   尺寸默认 512（精灵与 UI 够用），要 2K 时显式传参。
5. **透明贴图不走 rembg。** Qwen-Image 2.1 支持用提示词包装直接输出 RGBA
   （`comfy_client.TRANSPARENT_TEMPLATE`，形如 "This is an RGBA format image with transparency.
   `<subject>`. The image has an alpha channel and a transparent background."）；
   精灵类资产默认 `--transparent`。已实测：512×512 输出 RGBA，75,942 个全透明像素、四角 alpha=0。
6. **成本记为 0**（`cost_cents=0`）：本地算力不计费。付费后端的成本口径不变。
7. **产物路径照旧遵守技能既有规则**：工作文件进 `tmp/asset-gen/`，被游戏加载的才进 `assets/`，
   并更新 `docs/asset-manifest.md`。
8. **失败必须显式报错，不允许静默回退到付费后端**——否则会出现"以为走本地、其实被扣费"。

## Rationale

- 项目本来就靠本地算力出美术（16 张 word spirit 与多批 `assets(bN)` 都是这么来的）。
  把这条路接进 asset-gen，等于把"每个词配一张图""给 26 个字母做变体"这类以前因成本不敢做的量
  变成可做——本 ADR 落笔时一次 512px 出图实测 **30 秒、成本 0**。
- 协议层单独成文件：`asset_gen.py` 只多一个分支，付费后端路径零改动、零回归；
  将来 ComfyUI 换版本或换模型，改一个文件即可。
- 用环境变量而非写死：这台是个人服务器，入口随时会变，而且"哪个入口通"已经出现过三次不同答案。
- **不做 DashScope shim**：shim 把"协议不匹配"从代码里挪到一个必须常驻的进程里，
  故障面反而更大；而 comfy 后端失败时错误信息能直接指回 `/prompt` 的 `node_errors`，可诊断性更好。
- 显式报错而不是回退付费后端：这条是为了"钱"——静默回退会让免费/付费的边界消失。

## Edge Cases and State

- **入口不可达 / 502 / DNS 拦截**：报出 `COMFY_URL` 与实际 HTTP 状态，并提示可用 SSH 隧道。
- **实例被其它任务占用**：`/prompt` 正常入队，客户端轮询到 `--timeout`（默认 1800 秒）才失败，
  轮询日志会打印已耗时，便于判断是排队还是卡死。
- **模型文件更换**：通过 `COMFY_UNET` / `COMFY_CLIP` / `COMFY_VAE` 覆盖，不改代码。
- **ComfyUI 升级导致节点改名**：`TextEncodeQwenImage21` 就曾一度不在节点表里
  （723 节点时缺失，修复后 798 节点时出现）。提交时 `/prompt` 会做校验并回传 `node_errors`，
  属可诊断失败；`comfy_client` 的模块文档记录了核验过的节点与输出顺序（positive(0)/negative(1)/latent(2)）。
- **画质不达标**：属资源评审问题而非后端问题。不达标产物留在 `tmp/asset-gen/`，
  不进 `assets/`，也不写进 `docs/asset-manifest.md`。
- **离线开发**：入口不可达时 `comfy` 后端不可用，付费后端（若有 key）与已有资产不受影响。

## Amendment（2026-09-23）：接上 reference-edit，以及那个会静默降级的坑

要把主人房底图拆成三层（`mirage_inn_owner_room_layer_{plate,lantern,scroll}.png`）时，
t2i 不够用——必须让模型**看着原图**在原位重画。补上的路径是
`comfy_client.build_edit_graph()` / `generate_from_refs()`：

```
UnetLoaderGGUF → KSampler ← TextEncodeQwenImage21(prompt, images.image_1..16, vae=VAELoader)
                              └ latent(输出 2) 直接当 KSampler.latent_image
```

1. **Autogrow 的键是顶层输入名 `images.image_1`，不是 `images` 的值。**
   `TextEncodeQwenImage21` 的参考图是 `io.Autogrow`，16 个槽位展开成节点 inputs 里
   字面量键 `images.image_1` … `images.image_16`（前端导出的 workflow 里也是这么写的）。
   `{"images": {"image_1": [...]}}`、`{"images": {"images.image_1": [...]}}`、
   `{"images": ["10", 0]}` **三种写法 `/prompt` 全部返回 200 且 `node_errors` 为空**，
   然后被静默丢弃——作业退化成纯 t2i，画出一张"看起来对、其实无关"的图。
   判别方法：`resolution=0` 时**有**参考图则输出等于参考图尺寸（32 的倍数），没有则是
   `resolution or 1024` 的正方形；`/history/<id>` 里存的 `prompt` 能看到实际入参。
2. **`resolution` 是像素预算不是边长**：0 = 保持每张参考图自己的尺寸（对齐到 32 的倍数），
   >0 = 缩到约 `resolution×resolution` 保持长宽比；输出跟随 `image_1`。没有 width/height。
3. **实测速度比本 ADR 正文里那次快一个量级**（ComfyUI 已从 0.30.0 升到 0.37.0，且那台机器
   RAM 540 GB）：192×352 / 20 步 ≈ 32 s，320×512 ≈ 33 s，544×768 ≈ 33 s。
   正文里"1024px ≈ 482 s"是旧数字，做预算时不要再用它吓自己。
4. **官方 Qwen-Image-Layered 模型没装**（`models/diffusion_models/` 只有
   `qwen_image_2.1_Q6_K.gguf`，VAE 只有 `qwen_image_2.1_vae_bf16`）。`EmptyQwenImageLayeredLatentImage`
   节点在，但配套的 `qwen_image_layered_bf16` + `qwen_image_layered_vae` 不在，
   而且官方模板自己写着 prompt"**不是**用来控制单层语义的"。所以"按语义点名分层"
   走不通，拆层要用上面的 reference-edit 逐件做。
5. **连 SSH 时可以直接读服务端源码**：`ssh -p 24122 netgpu@wgma.bbxyard.com`，
   ComfyUI 在 `/home/netgpu/video-gen/ComfyUI-raylight`，`comfy_extras/nodes_qwen.py`
   是节点语义的权威，比猜 API 快。
