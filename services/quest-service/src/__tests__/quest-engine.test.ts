import { test, expect, describe } from 'vitest'
import { QuestEngine } from '../services/quest-engine'

describe('getUserQuests', () => {
  test('returns chapter 1 quests', async () => {
    const engine = new QuestEngine()
    const quests = await engine.getUserQuests('user-1')
    expect(quests.length).toBeGreaterThan(0)
  })

  test('returns all 12 quests (3 main + 9 sub)', async () => {
    const engine = new QuestEngine()
    const quests = await engine.getUserQuests('user-1')
    expect(quests.length).toBe(12)
  })

  test('filters by scene_id', async () => {
    const engine = new QuestEngine()
    const quests = await engine.getUserQuests('user-1', 'spirit_forest')
    expect(quests.length).toBe(4) // 1 main + 3 sub
    expect(quests.every((q) => q.scene_id === 'spirit_forest')).toBe(true)
  })

  test('quest_forest_main exists with correct fields', async () => {
    const engine = new QuestEngine()
    const quests = await engine.getUserQuests('user-1')
    const forestMain = quests.find((q) => q.quest_id === 'quest_forest_main')
    expect(forestMain).toBeDefined()
    expect(forestMain!.title).toBe('探索精灵森林')
    expect(forestMain!.title_en).toBe('Explore the Spirit Forest')
    expect(forestMain!.quest_type).toBe('main')
    expect(forestMain!.scene_id).toBe('spirit_forest')
  })

  test('sub-quests have parent_quest_id', async () => {
    const engine = new QuestEngine()
    const quests = await engine.getUserQuests('user-1')
    const subQuests = quests.filter((q) => q.quest_type === 'sub')
    expect(subQuests.every((q) => q.parent_quest_id)).toBe(true)
  })
})

describe('completeQuest', () => {
  test('calculates LXP correctly', async () => {
    const engine = new QuestEngine()
    const result = await engine.completeQuest('user-1', 'greet_oakley', {
      accuracy: 80,
      fluency: 70,
      vocabulary: 90,
    })

    expect(result.success).toBe(true)
    // LXP = 80*0.4 + 70*0.3 + 90*0.3 = 32 + 21 + 27 = 80
    expect(result.lxp_earned).toBe(80)
    expect(result.accuracy_score).toBe(80)
  })

  test('returns 3 stars for high scores (avg >= 90)', async () => {
    const engine = new QuestEngine()
    const result = await engine.completeQuest('user-2', 'greet_oakley', {
      accuracy: 95,
      fluency: 92,
      vocabulary: 93,
    })
    expect(result.stars_earned).toBe(3)
  })

  test('returns 2 stars for medium scores (avg >= 70)', async () => {
    const engine = new QuestEngine()
    const result = await engine.completeQuest('user-3', 'greet_oakley', {
      accuracy: 75,
      fluency: 70,
      vocabulary: 72,
    })
    expect(result.stars_earned).toBe(2)
  })

  test('returns 1 star for low scores (avg >= 40)', async () => {
    const engine = new QuestEngine()
    const result = await engine.completeQuest('user-4', 'greet_oakley', {
      accuracy: 50,
      fluency: 40,
      vocabulary: 45,
    })
    expect(result.stars_earned).toBe(1)
  })

  test('returns 0 stars for very low scores (avg < 40)', async () => {
    const engine = new QuestEngine()
    const result = await engine.completeQuest('user-5', 'greet_oakley', {
      accuracy: 20,
      fluency: 15,
      vocabulary: 25,
    })
    expect(result.stars_earned).toBe(0)
  })

  test('returns failure for unknown quest', async () => {
    const engine = new QuestEngine()
    const result = await engine.completeQuest('user-1', 'nonexistent_quest', {
      accuracy: 80,
      fluency: 80,
      vocabulary: 80,
    })
    expect(result.success).toBe(false)
    expect(result.lxp_earned).toBe(0)
  })

  test('unlocks badge when all sub-quests in a scene are complete', async () => {
    const engine = new QuestEngine()
    const userId = 'badge-test-user'

    // Complete all 3 forest sub-quests
    await engine.completeQuest(userId, 'greet_oakley', { accuracy: 90, fluency: 90, vocabulary: 90 })
    await engine.completeQuest(userId, 'activate_flowers', { accuracy: 90, fluency: 90, vocabulary: 90 })
    const forestResult = await engine.completeQuest(userId, 'open_chest', {
      accuracy: 90,
      fluency: 90,
      vocabulary: 90,
    })

    expect(forestResult.badge_unlocked).toBe('badge_spirit_forest')
  })

  test('does not unlock badge if scene is incomplete', async () => {
    const engine = new QuestEngine()
    const userId = 'incomplete-test-user'

    // Only complete 2 of 3 forest sub-quests
    await engine.completeQuest(userId, 'greet_oakley', { accuracy: 90, fluency: 90, vocabulary: 90 })
    const result = await engine.completeQuest(userId, 'activate_flowers', {
      accuracy: 90,
      fluency: 90,
      vocabulary: 90,
    })

    expect(result.badge_unlocked).toBe(null)
  })

  test('does not double-unlock badge', async () => {
    const engine = new QuestEngine()
    const userId = 'double-unlock-user'

    // Complete all forest sub-quests
    await engine.completeQuest(userId, 'greet_oakley', { accuracy: 90, fluency: 90, vocabulary: 90 })
    await engine.completeQuest(userId, 'activate_flowers', { accuracy: 90, fluency: 90, vocabulary: 90 })
    const result1 = await engine.completeQuest(userId, 'open_chest', {
      accuracy: 90,
      fluency: 90,
      vocabulary: 90,
    })
    expect(result1.badge_unlocked).toBe('badge_spirit_forest')

    // Complete a sub-quest again (simulating re-complete)
    const result2 = await engine.completeQuest(userId, 'greet_oakley', {
      accuracy: 90,
      fluency: 90,
      vocabulary: 90,
    })
    expect(result2.badge_unlocked).toBe(null)
  })
})

describe('generateDailyQuests', () => {
  test('returns 3 daily quests', async () => {
    const engine = new QuestEngine()
    const quests = await engine.generateDailyQuests('user-1')
    expect(quests.length).toBe(3)
    expect(quests.every((q) => q.quest_type === 'daily')).toBe(true)
  })

  test('daily quests have bilingual fields', async () => {
    const engine = new QuestEngine()
    const quests = await engine.generateDailyQuests('user-1')
    quests.forEach((q) => {
      expect(q.title).toBeDefined()
      expect(q.title_en).toBeDefined()
      expect(q.description).toBeDefined()
      expect(q.description_en).toBeDefined()
    })
  })
})

describe('getUserStars and getUserBadges', () => {
  test('getUserStars tracks accumulated stars', async () => {
    const engine = new QuestEngine()
    const userId = 'star-test-user'

    await engine.completeQuest(userId, 'greet_oakley', { accuracy: 95, fluency: 95, vocabulary: 95 })
    await engine.completeQuest(userId, 'activate_flowers', { accuracy: 95, fluency: 95, vocabulary: 95 })

    const stars = await engine.getUserStars(userId)
    expect(stars).toBe(6) // 3 + 3
  })

  test('getUserBadges returns unlocked badges', async () => {
    const engine = new QuestEngine()
    const userId = 'badge-list-user'

    // Complete all forest sub-quests
    await engine.completeQuest(userId, 'greet_oakley', { accuracy: 90, fluency: 90, vocabulary: 90 })
    await engine.completeQuest(userId, 'activate_flowers', { accuracy: 90, fluency: 90, vocabulary: 90 })
    await engine.completeQuest(userId, 'open_chest', { accuracy: 90, fluency: 90, vocabulary: 90 })

    const badges = await engine.getUserBadges(userId)
    expect(badges).toContain('badge_spirit_forest')
  })

  test('no badges before completing a scene', async () => {
    const engine = new QuestEngine()
    const badges = await engine.getUserBadges('fresh-user')
    expect(badges.length).toBe(0)
  })
})
