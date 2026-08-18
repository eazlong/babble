# ASR 测试模式音频目录

打开 `hybrid_api/asr_default_answer_test_enabled` 后，VoicePipeline 会跳过麦克风，
按文件名排序轮换使用本目录下的 `.wav` 文件作为真实 ASR 的输入。

文件命名建议按轮换顺序，例如 `01_hello.wav`、`02_carl.wav` ...
