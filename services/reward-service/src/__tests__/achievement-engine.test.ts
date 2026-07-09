import { test, expect, describe } from 'vitest'
import { UserStateManager } from '../services/user-state-manager'
import { AchievementEngine, DEFAULT_ACHIEVEMENTS } from '../services/achievement-engine'

function createEngine() {
  const userState = new UserStateManager()
  const achievementEngine = new AchievementEngine(userState)
  return { userState, achievementEngine }
}

describe('AchievementEngine', () => {
  test('getAll returns non-hidden achievements by default', () => {
    const { achievementEngine } = createEngine()
    const all = achievementEngine.getAll(false)
    const hidden = all.filter((a) => a.is_hidden)

    expect(hidden.length).toBe(0)
  })

  test('getAll with includeHidden returns all', () => {
    const { achievementEngine } = createEngine()
    const all = achievementEngine.getAll(true)

    expect(all.length).toBeGreaterThan(0)
  })

  test('getById returns correct achievement', () => {
    const { achievementEngine } = createEngine()
    const ach = achievementEngine.getById('ach_first_steps')

    expect(ach).toBeDefined()
    expect(ach!.name).toBe('第一步')
  })

  test('checkAll unlocks achievement when condition met', () => {
    const { userState, achievementEngine } = createEngine()

    // Give user 100 XP — should trigger ach_first_steps (xp_reach: 100)
    userState.addXP('user-1', 100)
    const unlocks = achievementEngine.checkAll('user-1')

    expect(unlocks.length).toBeGreaterThanOrEqual(1)
    const firstSteps = unlocks.find((u) => u.achievement.id === 'ach_first_steps')
    expect(firstSteps).toBeDefined()
  })

  test('checkAll does not double-complete', () => {
    const { userState, achievementEngine } = createEngine()

    userState.addXP('user-1', 100)
    const first = achievementEngine.checkAll('user-1')
    const second = achievementEngine.checkAll('user-1')

    expect(second.length).toBe(0)
  })

  test('achievement grants XP reward', () => {
    const { userState, achievementEngine } = createEngine()

    userState.addXP('user-1', 100)
    achievementEngine.checkAll('user-1')

    // ach_first_steps gives 50 XP bonus
    const state = userState.getState('user-1')
    expect(state.xp_total).toBe(150) // 100 + 50
  })

  test('calculateProgress returns correct ratio for xp_reach', () => {
    const { userState, achievementEngine } = createEngine()
    userState.addXP('user-1', 50)
    const state = userState.getState('user-1')

    const ach = achievementEngine.getById('ach_first_steps')!
    const progress = achievementEngine.calculateProgress(ach, state)

    expect(progress).toBe(0.5) // 50/100
  })

  test('calculateProgress caps at 1.0', () => {
    const { userState, achievementEngine } = createEngine()
    userState.addXP('user-1', 200)
    const state = userState.getState('user-1')

    const ach = achievementEngine.getById('ach_first_steps')!
    const progress = achievementEngine.calculateProgress(ach, state)

    expect(progress).toBe(1.0)
  })

  test('badge_count achievement triggers correctly', () => {
    const { userState, achievementEngine } = createEngine()

    userState.addBadge('user-1', 'badge_a')
    userState.addBadge('user-1', 'badge_b')
    userState.addBadge('user-1', 'badge_c')

    const unlocks = achievementEngine.checkAll('user-1')
    const collector = unlocks.find((u) => u.achievement.id === 'ach_collector')
    expect(collector).toBeDefined()
  })

  test('area_unlock_count achievement triggers correctly', () => {
    const { userState, achievementEngine } = createEngine()

    userState.unlockArea('user-1', 'area_a')
    userState.unlockArea('user-1', 'area_b')

    const unlocks = achievementEngine.checkAll('user-1')
    const explorer = unlocks.find((u) => u.achievement.id === 'ach_explorer_areas')
    expect(explorer).toBeDefined()
  })

  test('getUserAchievements returns progress for user', () => {
    const { userState, achievementEngine } = createEngine()

    userState.addXP('user-1', 50)
    const progress = achievementEngine.getUserAchievements('user-1')

    // No achievements completed yet at 50 XP
    expect(progress.length).toBe(0)
  })

  test('completed achievement has correct metadata', () => {
    const { userState, achievementEngine } = createEngine()

    userState.addXP('user-1', 100)
    achievementEngine.checkAll('user-1')

    const progress = achievementEngine.getUserAchievement('user-1', 'ach_first_steps')
    expect(progress).toBeDefined()
    expect(progress!.is_completed).toBe(true)
    expect(progress!.progress).toBe(1.0)
    expect(progress!.completed_at).not.toBeNull()
    expect(progress!.reward_grant_id).not.toBeNull()
  })

  test('setCustomProgress stores progress for quest conditions', () => {
    const { achievementEngine } = createEngine()

    achievementEngine.setCustomProgress('user-1', 'ach_quest_special', 0.75)
    const progress = achievementEngine.getUserAchievement('user-1', 'ach_quest_special')

    expect(progress).toBeDefined()
    expect(progress!.progress).toBe(0.75)
    expect(progress!.is_completed).toBe(false)
  })

  test('getCountByCategory filters correctly', () => {
    const { achievementEngine } = createEngine()

    const progression = achievementEngine.getCountByCategory('progression')
    expect(progression).toBeGreaterThan(0)

    const total = achievementEngine.getCountByCategory()
    expect(total).toBe(DEFAULT_ACHIEVEMENTS.length)
  })

  test('register adds new achievement', () => {
    const { achievementEngine } = createEngine()

    achievementEngine.register({
      id: 'ach_custom_test',
      name: 'Test Achievement',
      description: 'A test achievement',
      category: 'test',
      condition: { type: 'xp_reach', target: '9999', description: 'XP >= 9999' },
      reward: { xp: 10 },
      icon: 'test_icon',
      is_hidden: false,
    })

    const ach = achievementEngine.getById('ach_custom_test')
    expect(ach).toBeDefined()
    expect(ach!.name).toBe('Test Achievement')
  })
})
