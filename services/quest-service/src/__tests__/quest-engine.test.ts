import { test, expect } from 'vitest'
import { QuestEngine } from '../services/quest-engine'

test('getUserQuests returns quests', async () => {
  const engine = new QuestEngine()
  const quests = await engine.getUserQuests('user-1')
  expect(quests.length).toBeGreaterThan(0)
  expect(quests[0].quest_id).toBe('quest_1')
})

test('completeQuest calculates LXP correctly', async () => {
  const engine = new QuestEngine()
  const result = await engine.completeQuest('user-1', 'quest_1', {
    accuracy: 80,
    fluency: 70,
    vocabulary: 90
  })

  expect(result.success).toBe(true)
  // LXP = 80*0.4 + 70*0.3 + 90*0.3 = 32 + 21 + 27 = 80
  expect(result.lxp_earned).toBe(80)
  expect(result.accuracy_score).toBe(80)
})

test('generateDailyQuests returns 3 quests', async () => {
  const engine = new QuestEngine()
  const quests = await engine.generateDailyQuests('user-1')
  expect(quests.length).toBe(3)
  expect(quests.every(q => q.quest_type === 'daily')).toBe(true)
})
