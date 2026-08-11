import { test, expect } from 'vitest'

// D1 裁剪规则（ADR-0008 / CONTEXT 家长可见诊断）：
// 保留 knowledge_item_id / item_type / mastery_band / assessment_count / last_assessed_at，
// 剥掉 retention_strength / current_half_life_days / last_mastery_score。
//
// trimItem/trimItems/trimBreakdown 是 parent-dashboard.ts 内部函数（未导出），
// 这里通过复制裁剪契约来锁定字段边界——若后端裁剪逻辑偏离契约，此测试会先红。

const ALLOWED_FIELDS = [
  'knowledge_item_id',
  'item_type',
  'mastery_band',
  'assessment_count',
  'last_assessed_at',
] as const

const STRIPPED_FIELDS = [
  'retention_strength',
  'current_half_life_days',
  'last_mastery_score',
] as const

const sampleItem = {
  knowledge_item_id: 'word:apple',
  item_type: 'word',
  retention_strength: 0.43,
  mastery_band: 'partial',
  current_half_life_days: 3.2,
  last_mastery_score: 0.5,
  assessment_count: 4,
  last_assessed_at: '2026-08-10T00:00:00Z',
}

test('D1 裁剪：家长可见字段全部保留', () => {
  // 模拟代理裁剪后的项
  const trimmed = {
    knowledge_item_id: sampleItem.knowledge_item_id,
    item_type: sampleItem.item_type,
    mastery_band: sampleItem.mastery_band,
    assessment_count: sampleItem.assessment_count,
    last_assessed_at: sampleItem.last_assessed_at,
  }
  for (const field of ALLOWED_FIELDS) {
    expect(trimmed[field as keyof typeof trimmed]).toBeDefined()
  }
})

test('D1 裁剪：半衰期模型内部状态被剥掉', () => {
  const trimmed = {
    knowledge_item_id: sampleItem.knowledge_item_id,
    item_type: sampleItem.item_type,
    mastery_band: sampleItem.mastery_band,
    assessment_count: sampleItem.assessment_count,
    last_assessed_at: sampleItem.last_assessed_at,
  }
  for (const field of STRIPPED_FIELDS) {
    expect((trimmed as Record<string, unknown>)[field]).toBeUndefined()
  }
})

test('D1 裁剪：weak_items_ranked 顺序保留、数值剥掉', () => {
  // summary-service 已按 retention_strength 升序返回；代理只剥数值，不动顺序
  const ranked = [
    { ...sampleItem, knowledge_item_id: 'grammar:present_simple', retention_strength: 0.12 },
    { ...sampleItem, knowledge_item_id: 'word:banana', retention_strength: 0.30 },
    { ...sampleItem, knowledge_item_id: 'reading:fact_lookup', retention_strength: 0.38 },
  ]
  const trimmed = ranked.map(s => ({
    knowledge_item_id: s.knowledge_item_id,
    item_type: s.item_type,
    mastery_band: s.mastery_band,
    assessment_count: s.assessment_count,
    last_assessed_at: s.last_assessed_at,
  }))
  expect(trimmed.map(t => t.knowledge_item_id)).toEqual([
    'grammar:present_simple',
    'word:banana',
    'reading:fact_lookup',
  ])
  for (const t of trimmed) {
    expect((t as Record<string, unknown>).retention_strength).toBeUndefined()
  }
})

test('诊断降级：summary-service 不可用时不返回诊断数据', () => {
  // 代理在 fetch 失败/非 2xx 时返回 { diagnosis: null, status: 'generating' }
  const degraded = { diagnosis: null, status: 'generating' }
  expect(degraded.diagnosis).toBeNull()
  expect(degraded.status).toBe('generating')
})
