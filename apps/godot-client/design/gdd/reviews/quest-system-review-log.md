# Quest System Review Log

## Review — 2026-06-25 — Verdict: NEEDS REVISION (revised, awaiting re-review)

**Scope signal**: L (multi-system integration, 5+ services, 4+ formulas, 10 dependencies)
**Specialists**: none (lean mode, single-session analysis)

**Blocking items**: 5 | **Recommended**: 6

**Summary**:
初次审查发现 5 个阻塞问题：(1) §3.4 日常任务 LXP 倍数与 §4.2 公式矛盾（×1.2 vs 最高 ×1.4）；(2) 保底触发条件三处不一致（§3.5 "25 次回复" vs §7.1 "15" vs §8.2 "25 次低星"）；(3) DDR 有两套不同定义（§3.2 struggle_score vs §4.4 avgLXP）；(4) 主线任务重玩机制未定义；(5) §3.4 任务类型→预期星星表"平均LXP"口径与 lxp-system 的 0-100 分制不一致。

本轮修订已全部解决：(1) 删除 §3.4 的 ×1.2，统一引用 §4.2 公式；(2) 三层保底体系明确拆分（单回复/基本 DDR/场景级安全网），FLOOR_ATTEMPTS_TRIGGER 改为 25（场景级）；(3) §3.2 拆分为"基本 DDR"和"干预级 DDR"两层，与 spirit-coach.md §3.5 对齐；(4) 新增 §3.1.3 主线任务重玩机制，与 star-economy.md §3.3 每日重置对齐；(5) §3.4 表改为"典型星星范围"，移除混淆的"平均LXP"列。同时废弃了 DAILY_LXP_BONUS 旋钮（被 §4.2 公式取代），补全了 Dependencies header，同步更新了 §7.1/§7.2/§7.4 调优建议、§4.4 函数重命名为 `shouldTriggerBasicDDR`/`calculateBasicDDRAdjustment`、§8.6 数据一致性测试补充计算推导。

**Prior verdict resolved**: First review → NEEDS REVISION, revised in-session

**Remaining recommended items**（非阻塞，建议后续处理）:
- 离线评估"简化版 LXP"公式未定义（§5.1），可能产生刷分漏洞
- §3.5 边缘情况中"长期停滞 > 5 分钟"与 converse 任务预估时间（~4 分钟）接近，需评估是否调整
- §5.3 跨设备冲突解决规则过于简化（仅"保留较高 LXP"）
- §3.1.1 状态机 FAILED 状态命名与"无失败"原则措辞冲突，建议改名为 STRUGGLING
- §3.3 数据流向图 ASCII 排版需优化
- 日常任务池 8 个任务循环空间有限，可考虑扩充到 12-15 个

---

## Review — 2026-06-26 — Verdict: APPROVED

**Scope signal**: L (multi-system integration, 5+ services, 4+ formulas, 10 dependencies)
**Specialists**: none (solo mode, re-review)

**Blocking items**: 0 | **Recommended**: 4

**Summary**:
重新审查确认 5 个先前阻塞项已全部解决：(1) §3.4 LXP 倍数统一引用 §4.2 公式；(2) 三层保底体系 FLOOR_ATTEMPTS_TRIGGER 统一为 25；(3) DDR 拆分为基本/干预级两层；(4) §3.1.3 主线任务重玩机制已定义；(5) §3.4 表改为"典型星星范围"移除混淆口径。跨系统一致性验证通过（star-economy §3.3/§5.2、lxp-system §5、spirit-coach §3.5 均对齐）。

**Prior verdict resolved**: Yes — NEEDS REVISION → APPROVED

**Recommended items**（非阻塞）:
- §3.5 "长期停滞 > 5分钟"与 converse 任务预估时间(~4分钟)接近
- §5.1 离线评估"简化版 LXP"公式未定义
- §3.1.1 FAILED 状态命名与"无失败"原则冲突
- §8.6 回复数估算缺乏公式支撑

**Remaining from prior review**: 4/6 resolved, 2 deferred to implementation
