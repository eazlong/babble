import { test, expect, describe } from 'vitest'
import { UserStateManager } from '../services/user-state-manager'

describe('UserStateManager', () => {
  test('getState creates new user with defaults', () => {
    const manager = new UserStateManager()
    const state = manager.getState('user-1')

    expect(state.user_id).toBe('user-1')
    expect(state.xp_total).toBe(0)
    expect(state.xp_level).toBe(1)
    expect(state.badges).toEqual([])
    expect(state.unlocked_areas).toEqual([])
    expect(state.grant_count).toBe(0)
  })

  test('getState returns same object on repeated calls', () => {
    const manager = new UserStateManager()
    const state1 = manager.getState('user-1')
    const state2 = manager.getState('user-1')

    expect(state1).toBe(state2)
  })

  test('getUserState returns null for unknown user', () => {
    const manager = new UserStateManager()
    expect(manager.getUserState('unknown')).toBeNull()
  })

  test('addXP increases xp_total and xp_level', () => {
    const manager = new UserStateManager()
    manager.getState('user-1') // create

    const result = manager.addXP('user-1', 150)
    const state = manager.getState('user-1')

    expect(state.xp_total).toBe(150)
    expect(state.xp_level).toBe(2)
    expect(result.leveled_up).toBe(true)
    expect(result.old_level).toBe(1)
    expect(result.new_level).toBe(2)
  })

  test('addXP stacks correctly', () => {
    const manager = new UserStateManager()
    manager.getState('user-1')

    manager.addXP('user-1', 50)
    manager.addXP('user-1', 60)

    const state = manager.getState('user-1')
    expect(state.xp_total).toBe(110)
    expect(state.xp_level).toBe(2)
  })

  test('addXP levels up at correct thresholds', () => {
    const manager = new UserStateManager()
    manager.getState('user-1')

    // Level 1 -> 2 at 100 XP
    manager.addXP('user-1', 100)
    expect(manager.getState('user-1').xp_level).toBe(2)

    // Level 2 -> 3 at 200 XP
    manager.addXP('user-1', 100)
    expect(manager.getState('user-1').xp_level).toBe(3)

    // Level 3 -> 11 at 1000 XP
    manager.addXP('user-1', 800)
    expect(manager.getState('user-1').xp_level).toBe(11)
  })

  test('addBadge adds unique badge', () => {
    const manager = new UserStateManager()
    const isNew = manager.addBadge('user-1', 'badge_first')

    expect(isNew).toBe(true)
    expect(manager.getState('user-1').badges).toContain('badge_first')
  })

  test('addBadge returns false for duplicate', () => {
    const manager = new UserStateManager()
    manager.addBadge('user-1', 'badge_first')
    const isNew = manager.addBadge('user-1', 'badge_first')

    expect(isNew).toBe(false)
    expect(manager.getState('user-1').badges.length).toBe(1)
  })

  test('unlockArea unlocks new area', () => {
    const manager = new UserStateManager()
    const isNew = manager.unlockArea('user-1', 'area_forest')

    expect(isNew).toBe(true)
    expect(manager.getState('user-1').unlocked_areas).toContain('area_forest')
  })

  test('unlockArea returns false for duplicate', () => {
    const manager = new UserStateManager()
    manager.unlockArea('user-1', 'area_forest')
    const isNew = manager.unlockArea('user-1', 'area_forest')

    expect(isNew).toBe(false)
  })

  test('grant_count increments on every grant', () => {
    const manager = new UserStateManager()
    manager.getState('user-1')

    manager.addXP('user-1', 10)
    manager.addBadge('user-1', 'badge_a')
    manager.unlockArea('user-1', 'area_x')

    expect(manager.getState('user-1').grant_count).toBe(3)
  })

  test('resetUser removes all state', () => {
    const manager = new UserStateManager()
    manager.addXP('user-1', 100)
    manager.resetUser('user-1')

    expect(manager.getUserState('user-1')).toBeNull()
  })

  test('getUserIds returns all tracked users', () => {
    const manager = new UserStateManager()
    manager.getState('user-1')
    manager.getState('user-2')
    manager.getState('user-3')

    const ids = manager.getUserIds()
    expect(ids).toContain('user-1')
    expect(ids).toContain('user-2')
    expect(ids).toContain('user-3')
    expect(ids.length).toBe(3)
  })
})
