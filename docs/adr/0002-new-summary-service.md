# 新建 summary-service 而非扩展 assessment-service

学习总结与掌握度体系需要一个归属服务。决定新建独立的 `summary-service`（Python/FastAPI），而不是把总结/掌握度逻辑塞进现有 `assessment-service`。

## 理由

总结/掌握度是一个有独立生命周期的领域：补评编排（调 voice-service 重跑 ASR、临界升级 LLM）、半衰期状态机、遗忘曲线聚合、人读报告生成。这些和 `assessment-service` 的"单次交互打分"职责不同，也和 `quest-service` 的"任务生成"职责不同。塞进任一现有服务会让那个服务背两个领域，且补评分层编排逻辑天然需要独立归宿。

单向依赖：summary-service 消费 assessment/voice 的评分与音频，产出掌握度供 quest-service 消费，无环。CONTEXT-MAP.md 的多 context 结构天然容纳第十个服务。

## 后果

多一个服务 = 多一处部署、监控、故障点。MVP 若要压服务数量，至少在 assessment-service 内为总结/掌握度保留独立目录与路由前缀，为将来拆分留缝。
