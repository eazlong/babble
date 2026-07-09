/**
 * Achievement engine — condition checking, progress tracking, and auto-triggering.
 * Works with UserStateManager to check achievements after each reward grant.
 */

import { UserStateManager, UserRewardState } from './user-state-manager.js'

export type AchievementConditionType =
  | 'xp_reach'
  | 'badge_count'
  | 'quest_complete'
  | 'area_unlock_count'
  | 'custom'

export interface AchievementCondition {
  type: AchievementConditionType
  target: string // threshold as string, or quest_id, etc.
  description: string
}

export interface AchievementReward {
  xp: number
  badge_id?: string
  badge_name?: string
  badge_description?: string
  badge_icon?: string
  area_id?: string
  area_name?: string
}

export interface Achievement {
  id: string
  name: string
  description: string
  category: string
  condition: AchievementCondition
  reward: AchievementReward
  icon: string
  is_hidden: boolean
}

export interface UserAchievement {
  user_id: string
  achievement_id: string
  progress: number // 0.0 - 1.0
  is_completed: boolean
  completed_at: string | null
  reward_grant_id: string | null
}

export interface AchievementUnlock {
  achievement: Achievement
  reward_grant_id: string
  reward: AchievementReward
}

// Default achievements for the game
export const DEFAULT_ACHIEVEMENTS: Achievement[] = [
  {
    id: 'ach_first_steps',
    name: '第一步',
    description: '累计获得 100 XP',
    category: 'progression',
    condition: { type: 'xp_reach', target: '100', description: 'XP total >= 100' },
    reward: { xp: 50, badge_id: 'badge_first_steps', badge_name: '初学者', badge_description: '迈出语言学习的第一步', badge_icon: 'badge_first' },
    icon: 'achievement_first_steps',
    is_hidden: false,
  },
  {
    id: 'ach_explorer',
    name: '探索者',
    description: '累计获得 500 XP',
    category: 'progression',
    condition: { type: 'xp_reach', target: '500', description: 'XP total >= 500' },
    reward: { xp: 100, area_id: 'area_spell_library', area_name: '咒语图书馆' },
    icon: 'achievement_explorer',
    is_hidden: false,
  },
  {
    id: 'ach_scholar',
    name: '小学者',
    description: '累计获得 1000 XP',
    category: 'progression',
    condition: { type: 'xp_reach', target: '1000', description: 'XP total >= 1000' },
    reward: { xp: 200, badge_id: 'badge_scholar', badge_name: '小学者', badge_description: '语言学习的小专家', badge_icon: 'badge_scholar' },
    icon: 'achievement_scholar',
    is_hidden: false,
  },
  {
    id: 'ach_collector',
    name: '收藏家',
    description: '收集 3 个徽章',
    category: 'collection',
    condition: { type: 'badge_count', target: '3', description: 'Badge count >= 3' },
    reward: { xp: 150, badge_id: 'badge_collector', badge_name: '收藏家', badge_description: '收集了多个徽章', badge_icon: 'badge_collector' },
    icon: 'achievement_collector',
    is_hidden: false,
  },
  {
    id: 'ach_explorer_areas',
    name: '地图开拓者',
    description: '解锁 2 个区域',
    category: 'exploration',
    condition: { type: 'area_unlock_count', target: '2', description: 'Area unlock count >= 2' },
    reward: { xp: 200, badge_id: 'badge_explorer', badge_name: '探险家', badge_description: '解锁了多个游戏区域', badge_icon: 'badge_explorer' },
    icon: 'achievement_explorer_areas',
    is_hidden: false,
  },
  {
    id: 'ach_master',
    name: '语言大师',
    description: '累计获得 5000 XP',
    category: 'progression',
    condition: { type: 'xp_reach', target: '5000', description: 'XP total >= 5000' },
    reward: { xp: 500, badge_id: 'badge_master', badge_name: '语言大师', badge_description: '达到最高语言水平', badge_icon: 'badge_master' },
    icon: 'achievement_master',
    is_hidden: true,
  },
]

export class AchievementEngine {
  private readonly achievements = new Map<string, Achievement>()
  private readonly userProgress = new Map<string, Map<string, UserAchievement>>()

  constructor(
    private readonly userState: UserStateManager,
    initialAchievements: Achievement[] = DEFAULT_ACHIEVEMENTS,
  ) {
    for (const ach of initialAchievements) {
      this.achievements.set(ach.id, ach)
    }
  }

  /** Register a new achievement. */
  register(achievement: Achievement): void {
    this.achievements.set(achievement.id, achievement)
  }

  /** Get all achievements (optionally filtered by visibility). */
  getAll(includeHidden = false): Achievement[] {
    return Array.from(this.achievements.values()).filter(
      (a) => includeHidden || !a.is_hidden,
    )
  }

  /** Get a single achievement by ID. */
  getById(id: string): Achievement | undefined {
    return this.achievements.get(id)
  }

  /** Get user's achievement progress. */
  getUserAchievements(userId: string): UserAchievement[] {
    const userMap = this.userProgress.get(userId)
    if (!userMap) return []
    return Array.from(userMap.values())
  }

  /** Check all achievements for a user and return any that were unlocked. */
  checkAll(userId: string): AchievementUnlock[] {
    const state = this.userState.getUserState(userId)
    if (!state) return []

    const unlocks: AchievementUnlock[] = []

    for (const achievement of this.achievements.values()) {
      const existing = this.getUserAchievement(userId, achievement.id)

      // Skip if already completed
      if (existing?.is_completed) continue

      const progress = this.calculateProgress(achievement, state)

      if (progress >= 1.0) {
        const unlock = this.completeAchievement(userId, achievement, state)
        if (unlock) unlocks.push(unlock)
      }
    }

    return unlocks
  }

  /** Calculate progress for a specific achievement. */
  calculateProgress(
    achievement: Achievement,
    state: UserRewardState,
  ): number {
    const threshold = parseFloat(achievement.condition.target)

    switch (achievement.condition.type) {
      case 'xp_reach':
        return Math.min(state.xp_total / threshold, 1.0)
      case 'badge_count':
        return Math.min(state.badges.length / threshold, 1.0)
      case 'area_unlock_count':
        return Math.min(state.unlocked_areas.length / threshold, 1.0)
      case 'quest_complete':
        // Quest progress is tracked externally; default 0
        return 0
      case 'custom':
        // Custom conditions checked externally
        return 0
      default:
        return 0
    }
  }

  /** Complete an achievement and grant its rewards. */
  private completeAchievement(
    userId: string,
    achievement: Achievement,
    state: UserRewardState,
  ): AchievementUnlock | null {
    // Grant XP reward
    if (achievement.reward.xp > 0) {
      this.userState.addXP(userId, achievement.reward.xp)
    }

    // Grant badge
    if (achievement.reward.badge_id) {
      this.userState.addBadge(userId, achievement.reward.badge_id)
    }

    // Unlock area
    if (achievement.reward.area_id) {
      this.userState.unlockArea(userId, achievement.reward.area_id)
    }

    const now = new Date().toISOString()
    const userAchievement: UserAchievement = {
      user_id: userId,
      achievement_id: achievement.id,
      progress: 1.0,
      is_completed: true,
      completed_at: now,
      reward_grant_id: `ach_grant_${achievement.id}_${Date.now()}`,
    }

    // Store progress
    let userMap = this.userProgress.get(userId)
    if (!userMap) {
      userMap = new Map()
      this.userProgress.set(userId, userMap)
    }
    userMap.set(achievement.id, userAchievement)

    return {
      achievement,
      reward_grant_id: userAchievement.reward_grant_id!,
      reward: achievement.reward,
    }
  }

  /** Get progress for a specific achievement. */
  getUserAchievement(
    userId: string,
    achievementId: string,
  ): UserAchievement | undefined {
    return this.userProgress.get(userId)?.get(achievementId)
  }

  /** Add a custom progress entry (for quest_complete or custom conditions). */
  setCustomProgress(
    userId: string,
    achievementId: string,
    progress: number,
  ): void {
    let userMap = this.userProgress.get(userId)
    if (!userMap) {
      userMap = new Map()
      this.userProgress.set(userId, userMap)
    }

    const existing = userMap.get(achievementId)
    if (existing && existing.is_completed) return // Already done

    userMap.set(achievementId, {
      user_id: userId,
      achievement_id: achievementId,
      progress: Math.min(progress, 1.0),
      is_completed: false,
      completed_at: null,
      reward_grant_id: null,
    })
  }

  /** Get achievement count by category. */
  getCountByCategory(category?: string): number {
    if (!category) return this.achievements.size
    return Array.from(this.achievements.values()).filter(
      (a) => a.category === category,
    ).length
  }
}
