import { test, expect, describe, beforeEach, vi } from 'vitest'
import { MemoryQuestStorage, SupabaseQuestStorage } from '../services/quest-storage.js'
import { QuestSessionManager, createQuestEvent } from '../services/quest-session-manager.js'

// ============================================================
// MemoryQuestStorage Tests
// ============================================================

describe('MemoryQuestStorage', () => {
  let storage: MemoryQuestStorage

  beforeEach(() => {
    storage = new MemoryQuestStorage()
  })

  describe('loadUserState', () => {
    test('returns empty state for new user', async () => {
      const state = await storage.loadUserState('new-user')
      expect(state.completed_quest_ids.size).toBe(0)
      expect(state.total_stars).toBe(0)
      expect(state.badges.size).toBe(0)
      expect(state.daily_quest_progress.size).toBe(0)
    })
  })

  describe('completeQuest', () => {
    test('records a quest completion', async () => {
      const record = await storage.completeQuest(
        'user-1', 'greet_oakley', 'spirit_forest',
        { accuracy: 80, fluency: 70, vocabulary: 90 },
        80, 2, null, [{ item_id: 'copper_coin', name: '铜币' }]
      )
      expect(record).not.toBeNull()
      expect(record!.quest_id).toBe('greet_oakley')
      expect(record!.lxp_earned).toBe(80)
    })

    test('returns null for duplicate (idempotent)', async () => {
      await storage.completeQuest(
        'user-1', 'greet_oakley', 'spirit_forest',
        { accuracy: 80, fluency: 70, vocabulary: 90 },
        80, 2, null, []
      )
      const second = await storage.completeQuest(
        'user-1', 'greet_oakley', 'spirit_forest',
        { accuracy: 90, fluency: 90, vocabulary: 90 },
        90, 3, null, []
      )
      expect(second).toBeNull()
    })

    test('different users can complete same quest', async () => {
      const r1 = await storage.completeQuest(
        'user-1', 'greet_oakley', 'spirit_forest',
        { accuracy: 80, fluency: 70, vocabulary: 90 }, 80, 2, null, []
      )
      const r2 = await storage.completeQuest(
        'user-2', 'greet_oakley', 'spirit_forest',
        { accuracy: 90, fluency: 90, vocabulary: 90 }, 90, 3, null, []
      )
      expect(r1).not.toBeNull()
      expect(r2).not.toBeNull()
    })
  })

  describe('updateUserStats', () => {
    test('persists stats and loads them back', async () => {
      await storage.updateUserStats('user-1', 15, ['badge_spirit_forest'])
      const state = await storage.loadUserState('user-1')
      expect(state.total_stars).toBe(15)
      expect(state.badges.has('badge_spirit_forest')).toBe(true)
      expect(state.scene_badges.has('badge_spirit_forest')).toBe(true)
    })

    test('overwrites previous stats', async () => {
      await storage.updateUserStats('user-1', 10, ['badge_a'])
      await storage.updateUserStats('user-1', 20, ['badge_a', 'badge_b'])
      const state = await storage.loadUserState('user-1')
      expect(state.total_stars).toBe(20)
      expect(state.badges.size).toBe(2)
    })
  })

  describe('loadUserState with completions', () => {
    test('loads completed quest ids and cached results', async () => {
      await storage.completeQuest(
        'user-1', 'greet_oakley', 'spirit_forest',
        { accuracy: 80, fluency: 70, vocabulary: 90 },
        80, 2, null, []
      )
      await storage.completeQuest(
        'user-1', 'activate_flowers', 'spirit_forest',
        { accuracy: 90, fluency: 85, vocabulary: 80 },
        85, 3, null, []
      )

      const state = await storage.loadUserState('user-1')
      expect(state.completed_quest_ids.has('greet_oakley')).toBe(true)
      expect(state.completed_quest_ids.has('activate_flowers')).toBe(true)
      expect(state.quest_results.has('greet_oakley')).toBe(true)
      expect(state.quest_results.get('greet_oakley')!.lxp_earned).toBe(80)
    })
  })

  describe('Daily Quests', () => {
    test('upsert and retrieve daily quests', async () => {
      const today = new Date().toISOString().slice(0, 10)
      await storage.upsertDailyQuest('user-1', today, 'daily_greet')
      await storage.upsertDailyQuest('user-1', today, 'daily_colors')

      const rows = await storage.getDailyQuests('user-1', today)
      expect(rows.length).toBe(2)
      expect(rows.some(r => r.quest_id === 'daily_greet')).toBe(true)
    })

    test('complete a daily quest', async () => {
      const today = new Date().toISOString().slice(0, 10)
      await storage.upsertDailyQuest('user-1', today, 'daily_greet')

      const result = await storage.completeDailyQuest('user-1', today, 'daily_greet', 3)
      expect(result.success).toBe(true)
      expect(result.alreadyCompleted).toBe(false)

      // Second completion should fail
      const result2 = await storage.completeDailyQuest('user-1', today, 'daily_greet', 3)
      expect(result2.success).toBe(false)
      expect(result2.alreadyCompleted).toBe(true)
    })

    test('different dates are independent', async () => {
      await storage.upsertDailyQuest('user-1', '2026-05-28', 'daily_greet')
      await storage.completeDailyQuest('user-1', '2026-05-28', 'daily_greet', 3)

      // Different date: quest should be available
      const rows = await storage.getDailyQuests('user-1', '2026-05-29')
      expect(rows.length).toBe(0)
    })

    test('cleanup old daily quests', async () => {
      await storage.upsertDailyQuest('user-1', '2026-05-27', 'daily_greet')
      await storage.upsertDailyQuest('user-1', '2026-05-28', 'daily_colors')

      await storage.cleanupOldDailyQuests('user-1', '2026-05-28')

      const old = await storage.getDailyQuests('user-1', '2026-05-27')
      expect(old.length).toBe(0) // cleaned up

      const current = await storage.getDailyQuests('user-1', '2026-05-28')
      expect(current.length).toBe(1) // still exists
    })
  })

  describe('clear', () => {
    test('clears all data', async () => {
      await storage.completeQuest('user-1', 'greet_oakley', 'spirit_forest',
        { accuracy: 80, fluency: 70, vocabulary: 90 }, 80, 2, null, [])
      await storage.updateUserStats('user-1', 10, ['badge_a'])
      storage.clear()

      const state = await storage.loadUserState('user-1')
      expect(state.completed_quest_ids.size).toBe(0)
      expect(state.total_stars).toBe(0)
      expect(state.badges.size).toBe(0)
    })
  })
})

// ============================================================
// SupabaseQuestStorage Tests
// ============================================================

describe('SupabaseQuestStorage', () => {
  test('constructor accepts SupabaseClient', () => {
    // Just verify the class can be instantiated with a mock client
    const mockClient = {} as any
    const storage = new SupabaseQuestStorage(mockClient)
    expect(storage).toBeDefined()
  })
})

// ============================================================
// QuestSessionManager Tests
// ============================================================

describe('QuestSessionManager', () => {
  let manager: QuestSessionManager

  beforeEach(() => {
    manager = new QuestSessionManager()
  })

  function createMockSocket(): any {
    return {
      readyState: 1, // OPEN
      send: vi.fn(),
      close: vi.fn(),
      on: vi.fn(),
    }
  }

  test('attach adds a connection', () => {
    const socket = createMockSocket()
    manager.attach('user-1', socket)
    expect(manager.getConnectionCount()).toBe(1)
  })

  test('attach replaces existing connection for same user', () => {
    const socket1 = createMockSocket()
    const socket2 = createMockSocket()
    manager.attach('user-1', socket1)
    manager.attach('user-1', socket2)
    expect(manager.getConnectionCount()).toBe(1)
    expect(socket1.close).toHaveBeenCalled()
  })

  test('detach removes a connection', () => {
    const socket = createMockSocket()
    manager.attach('user-1', socket)
    manager.detach('user-1')
    expect(manager.getConnectionCount()).toBe(0)
  })

  test('sendToUser sends JSON to the socket', () => {
    const socket = createMockSocket()
    manager.attach('user-1', socket)
    const event = createQuestEvent('quest_completed', { quest_id: 'greet_oakley', lxp_earned: 80 })
    const result = manager.sendToUser('user-1', event)
    expect(result).toBe(true)
    expect(socket.send).toHaveBeenCalled()
  })

  test('sendToUser returns false for non-existent user', () => {
    const event = createQuestEvent('quest_completed', {})
    const result = manager.sendToUser('nonexistent', event)
    expect(result).toBe(false)
  })

  test('sendToUser returns false for closed socket', () => {
    const socket = createMockSocket()
    socket.readyState = 3 // CLOSED
    manager.attach('user-1', socket)
    const event = createQuestEvent('quest_completed', {})
    const result = manager.sendToUser('user-1', event)
    expect(result).toBe(false)
  })

  test('cleanup removes closed connections', () => {
    const socket = createMockSocket()
    manager.attach('user-1', socket)
    socket.readyState = 3 // CLOSED
    manager.cleanup()
    expect(manager.getConnectionCount()).toBe(0)
  })
})

// ============================================================
// createQuestEvent Tests
// ============================================================

describe('createQuestEvent', () => {
  test('creates a valid event with timestamp', () => {
    const event = createQuestEvent('badge_unlocked', { badge_id: 'badge_spirit_forest' })
    expect(event.type).toBe('badge_unlocked')
    expect(event.payload.badge_id).toBe('badge_spirit_forest')
    expect(event.timestamp).toBeDefined()
    // Timestamp should be a valid ISO string
    expect(new Date(event.timestamp).toISOString()).toBe(event.timestamp)
  })
})
