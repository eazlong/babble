/**
 * User reward state manager — tracks XP, badges, and unlocked areas per user.
 * In-memory Map-based storage.
 */

export interface UserRewardState {
  user_id: string
  xp_total: number
  xp_level: number
  badges: string[]
  unlocked_areas: string[]
  grant_count: number
}

export interface XPResult {
  old_level: number
  new_level: number
  leveled_up: boolean
}

export class UserStateManager {
  private readonly states = new Map<string, UserRewardState>()

  getState(userId: string): UserRewardState {
    let state = this.states.get(userId)
    if (!state) {
      state = {
        user_id: userId,
        xp_total: 0,
        xp_level: 1,
        badges: [],
        unlocked_areas: [],
        grant_count: 0,
      }
      this.states.set(userId, state)
    }
    return state
  }

  getUserState(userId: string): UserRewardState | null {
    return this.states.get(userId) ?? null
  }

  addXP(userId: string, amount: number): XPResult {
    const state = this.getState(userId)
    const oldLevel = state.xp_level
    state.xp_total += amount
    state.xp_level = Math.floor(state.xp_total / 100) + 1
    state.grant_count += 1
    return {
      old_level: oldLevel,
      new_level: state.xp_level,
      leveled_up: state.xp_level > oldLevel,
    }
  }

  addBadge(userId: string, badgeId: string): boolean {
    const state = this.getState(userId)
    if (state.badges.includes(badgeId)) {
      return false
    }
    state.badges.push(badgeId)
    state.grant_count += 1
    return true
  }

  unlockArea(userId: string, areaId: string): boolean {
    const state = this.getState(userId)
    if (state.unlocked_areas.includes(areaId)) {
      return false
    }
    state.unlocked_areas.push(areaId)
    state.grant_count += 1
    return true
  }

  resetUser(userId: string): void {
    this.states.delete(userId)
  }

  getUserIds(): string[] {
    return Array.from(this.states.keys())
  }
}
