# LinguaQuest E2E 测试

## 运行测试

```bash
# 安装依赖
pnpm install

# 启动所有服务
cd .. && pnpm dev

# 运行 E2E 测试
pnpm test:e2e

# 运行性能测试
pnpm test:perf

# 生成性能报告
pnpm test:perf:report

# 运行全部测试
pnpm test:all
```

## 测试覆盖

| 文件 | 覆盖范围 |
|------|----------|
| `voice-pipeline.test.ts` | 语音管线：ASR → LLM → TTS 完整流程 |
| `quest-flow.test.ts` | 任务接受、完成、进度持久化 |
| `child-mode.test.ts` | 儿童模式、时间限制、内容过滤、家长控制台 |
| `reward-drop.test.ts` | LXP 奖励、徽章、语法纠错、奖励面板 |
| `chapter1-flow.test.ts` | 第一章完整流程、词汇互动、精灵教练、降级重试、徽章收集 |

## 环境要求

- 所有微服务运行中 (`pnpm dev`)
- Parent Dashboard 运行在 `localhost:3300`
- 可选：设置 `TEST_API_TOKEN` 和 `TEST_USER_ID` 环境变量

## 报告

测试完成后 HTML 报告生成在 `e2e-report/` 目录。
