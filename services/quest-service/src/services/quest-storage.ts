import type { SupabaseClient } from "@supabase/supabase-js"

// ============================================================
// Types — mirror the in-memory QuestState shape
// ============================================================

export interface CompletionRecord {
  quest_id: string
  scene_id: string
  accuracy: number
  fluency: number
  vocabulary: number
  lxp_earned: number
  stars_earned: number
  badge_unlocked: string | null
  rewards: Array<{ item_id: string; name: string }>
  completed_at: string
}

export interface UserQuestState {
  completed_quest_ids: Set<string>
  completed_sub_quests: Set<string>
  scene_badges: Set<string>
  total_stars: number
  badges: Set<string>
  daily_quest_date: string
  daily_quest_progress: Map<string, { quest_id: string; completed: boolean; stars_earned: number }>
  // Idempotency cache: last result per quest_id
  quest_results: Map<string, {
    success: boolean
    lxp_earned: number
    accuracy_score: number
    fluency_score: number
    vocabulary_score: number
    stars_earned: number
    badge_unlocked: string | null
    rewards: Array<{ item_id: string; name: string }>
    all_scene_quests_complete: boolean
  }>
}

export interface DailyQuestRow {
  quest_id: string
  completed: boolean
  stars_earned: number
}

// ============================================================
// Storage Interface
// ============================================================

export interface QuestStorage {
  /** Load or create a user's full quest state */
  loadUserState(userId: string): Promise<UserQuestState>

  /**
   * Record quest completion. Returns existing record if already completed
   * (idempotent), or the newly created record.
   */
  completeQuest(
    userId: string,
    questId: string,
    sceneId: string,
    scores: { accuracy: number; fluency: number; vocabulary: number },
    lxp_earned: number,
    stars_earned: number,
    badge_unlocked: string | null,
    rewards: Array<{ item_id: string; name: string }>
  ): Promise<CompletionRecord | null>

  /** Update user's total_stars and badges */
  updateUserStats(userId: string, total_stars: number, badges: string[]): Promise<void>

  /** Get today's daily quest state for a user */
  getDailyQuests(userId: string, date: string): Promise<DailyQuestRow[]>

  /** Upsert a daily quest row (for generation) */
  upsertDailyQuest(userId: string, date: string, questId: string): Promise<void>

  /** Complete a daily quest */
  completeDailyQuest(
    userId: string,
    date: string,
    questId: string,
    stars_earned: number
  ): Promise<{ success: boolean; alreadyCompleted: boolean }>

  /** Clean up stale daily quests for a user (before given date) */
  cleanupOldDailyQuests(userId: string, beforeDate: string): Promise<void>
}

// ============================================================
// Supabase Implementation
// ============================================================

export class SupabaseQuestStorage implements QuestStorage {
  constructor(private supabase: SupabaseClient) {}

  async loadUserState(userId: string): Promise<UserQuestState> {
    const state: UserQuestState = {
      completed_quest_ids: new Set(),
      completed_sub_quests: new Set(),
      scene_badges: new Set(),
      total_stars: 0,
      badges: new Set(),
      daily_quest_date: "",
      daily_quest_progress: new Map(),
      quest_results: new Map(),
    }

    // Load quest completions
    const { data: completions, error: questErr } = await this.supabase
      .from("user_quest_completion")
      .select("*")
      .eq("user_id", userId)
      .order("completed_at", { ascending: true })

    if (questErr) {
      console.warn(`[quest-storage] Failed to load quest completions for ${userId}:`, questErr.message)
      return state
    }

    for (const row of completions || []) {
      state.completed_quest_ids.add(row.quest_id)
      // Sub-quests: infer from CHAPTER_1_QUESTS in quest-engine (handled there)
      // We store the full completion for quest_results cache
      state.quest_results.set(row.quest_id, {
        success: true,
        lxp_earned: row.lxp_earned,
        accuracy_score: row.accuracy,
        fluency_score: row.fluency,
        vocabulary_score: row.vocabulary,
        stars_earned: row.stars_earned,
        badge_unlocked: row.badge_unlocked,
        rewards: row.rewards,
        all_scene_quests_complete: false, // computed at runtime
      })
    }

    // Load user stats
    const { data: stats, error: statsErr } = await this.supabase
      .from("user_stats")
      .select("total_stars, badges")
      .eq("user_id", userId)
      .single()

    if (!statsErr && stats) {
      state.total_stars = stats.total_stars || 0
      if (Array.isArray(stats.badges)) {
        for (const b of stats.badges) {
          state.badges.add(b)
          state.scene_badges.add(b)
        }
      }
    }

    // Load today's daily quests
    const today = new Date().toISOString().slice(0, 10)
    state.daily_quest_date = today
    const { data: daily, error: dailyErr } = await this.supabase
      .from("daily_quest_state")
      .select("quest_id, completed, stars_earned")
      .eq("user_id", userId)
      .eq("quest_date", today)

    if (!dailyErr && daily) {
      for (const row of daily) {
        state.daily_quest_progress.set(row.quest_id, {
          quest_id: row.quest_id,
          completed: row.completed,
          stars_earned: row.stars_earned,
        })
      }
    }

    return state
  }

  async completeQuest(
    userId: string,
    questId: string,
    sceneId: string,
    scores: { accuracy: number; fluency: number; vocabulary: number },
    lxp_earned: number,
    stars_earned: number,
    badge_unlocked: string | null,
    rewards: Array<{ item_id: string; name: string }>
  ): Promise<CompletionRecord | null> {
    // Try insert — UNIQUE constraint handles idempotency
    const { data, error } = await this.supabase
      .from("user_quest_completion")
      .insert({
        user_id: userId,
        quest_id: questId,
        scene_id: sceneId,
        accuracy: scores.accuracy,
        fluency: scores.fluency,
        vocabulary: scores.vocabulary,
        lxp_earned,
        stars_earned,
        badge_unlocked,
        rewards,
      })
      .select()
      .single()

    if (error) {
      // UNIQUE violation → already completed, return null to signal "no-op"
      if (error.code === "23505") {
        return null
      }
      console.warn(`[quest-storage] Failed to complete quest ${questId} for ${userId}:`, error.message)
      return null
    }

    return {
      quest_id: data.quest_id,
      scene_id: data.scene_id,
      accuracy: data.accuracy,
      fluency: data.fluency,
      vocabulary: data.vocabulary,
      lxp_earned: data.lxp_earned,
      stars_earned: data.stars_earned,
      badge_unlocked: data.badge_unlocked,
      rewards: data.rewards,
      completed_at: data.completed_at,
    }
  }

  async updateUserStats(userId: string, total_stars: number, badges: string[]): Promise<void> {
    const { error } = await this.supabase
      .from("user_stats")
      .upsert(
        { user_id: userId, total_stars, badges, updated_at: new Date().toISOString() },
        { onConflict: "user_id" }
      )

    if (error) {
      console.warn(`[quest-storage] Failed to update stats for ${userId}:`, error.message)
    }
  }

  async getDailyQuests(userId: string, date: string): Promise<DailyQuestRow[]> {
    const { data, error } = await this.supabase
      .from("daily_quest_state")
      .select("quest_id, completed, stars_earned")
      .eq("user_id", userId)
      .eq("quest_date", date)

    if (error) {
      console.warn(`[quest-storage] Failed to load daily quests for ${userId}:`, error.message)
      return []
    }

    return (data || []).map((row) => ({
      quest_id: row.quest_id,
      completed: row.completed,
      stars_earned: row.stars_earned,
    }))
  }

  async upsertDailyQuest(userId: string, date: string, questId: string): Promise<void> {
    const { error } = await this.supabase
      .from("daily_quest_state")
      .upsert(
        { user_id: userId, quest_date: date, quest_id: questId, completed: false, stars_earned: 0 },
        { onConflict: "user_id,quest_date,quest_id", ignoreDuplicates: true }
      )

    if (error) {
      console.warn(`[quest-storage] Failed to upsert daily quest ${questId}:`, error.message)
    }
  }

  async completeDailyQuest(
    userId: string,
    date: string,
    questId: string,
    stars_earned: number
  ): Promise<{ success: boolean; alreadyCompleted: boolean }> {
    // First check if already completed
    const { data: existing } = await this.supabase
      .from("daily_quest_state")
      .select("completed")
      .eq("user_id", userId)
      .eq("quest_date", date)
      .eq("quest_id", questId)
      .single()

    if (existing?.completed) {
      return { success: false, alreadyCompleted: true }
    }

    // Upsert with completed = true
    const { error } = await this.supabase
      .from("daily_quest_state")
      .upsert(
        { user_id: userId, quest_date: date, quest_id: questId, completed: true, stars_earned },
        { onConflict: "user_id,quest_date,quest_id" }
      )

    if (error) {
      console.warn(`[quest-storage] Failed to complete daily quest ${questId}:`, error.message)
      return { success: false, alreadyCompleted: false }
    }

    return { success: true, alreadyCompleted: false }
  }

  async cleanupOldDailyQuests(userId: string, beforeDate: string): Promise<void> {
    const { error } = await this.supabase
      .from("daily_quest_state")
      .delete()
      .eq("user_id", userId)
      .lt("quest_date", beforeDate)

    if (error) {
      console.warn(`[quest-storage] Failed to cleanup old daily quests:`, error.message)
    }
  }
}

// ============================================================
// Memory Implementation (fallback for tests & Supabase unavailable)
// ============================================================

export class MemoryQuestStorage implements QuestStorage {
  private questCompletions = new Map<string, CompletionRecord>()
  private userStats = new Map<string, { total_stars: number; badges: string[] }>()
  private dailyQuests = new Map<string, DailyQuestRow[]>()

  async loadUserState(userId: string): Promise<UserQuestState> {
    const state: UserQuestState = {
      completed_quest_ids: new Set(),
      completed_sub_quests: new Set(),
      scene_badges: new Set(),
      total_stars: 0,
      badges: new Set(),
      daily_quest_date: "",
      daily_quest_progress: new Map(),
      quest_results: new Map(),
    }

    // Load completions
    for (const [key, record] of this.questCompletions) {
      if (key.startsWith(`${userId}:`)) {
        state.completed_quest_ids.add(record.quest_id)
        state.quest_results.set(record.quest_id, {
          success: true,
          lxp_earned: record.lxp_earned,
          accuracy_score: record.accuracy,
          fluency_score: record.fluency,
          vocabulary_score: record.vocabulary,
          stars_earned: record.stars_earned,
          badge_unlocked: record.badge_unlocked,
          rewards: record.rewards,
          all_scene_quests_complete: false,
        })
      }
    }

    // Load stats
    const stats = this.userStats.get(userId)
    if (stats) {
      state.total_stars = stats.total_stars
      for (const b of stats.badges) {
        state.badges.add(b)
        state.scene_badges.add(b)
      }
    }

    // Load daily quests
    const today = new Date().toISOString().slice(0, 10)
    state.daily_quest_date = today
    const daily = this.dailyQuests.get(`${userId}:${today}`)
    if (daily) {
      for (const row of daily) {
        state.daily_quest_progress.set(row.quest_id, {
          quest_id: row.quest_id,
          completed: row.completed,
          stars_earned: row.stars_earned,
        })
      }
    }

    return state
  }

  async completeQuest(
    userId: string,
    questId: string,
    sceneId: string,
    scores: { accuracy: number; fluency: number; vocabulary: number },
    lxp_earned: number,
    stars_earned: number,
    badge_unlocked: string | null,
    rewards: Array<{ item_id: string; name: string }>
  ): Promise<CompletionRecord | null> {
    const key = `${userId}:${questId}`
    const existing = this.questCompletions.get(key)
    if (existing) return null // idempotent

    const record: CompletionRecord = {
      quest_id: questId,
      scene_id: sceneId,
      accuracy: scores.accuracy,
      fluency: scores.fluency,
      vocabulary: scores.vocabulary,
      lxp_earned,
      stars_earned,
      badge_unlocked,
      rewards,
      completed_at: new Date().toISOString(),
    }
    this.questCompletions.set(key, record)
    return record
  }

  async updateUserStats(userId: string, total_stars: number, badges: string[]): Promise<void> {
    this.userStats.set(userId, { total_stars, badges })
  }

  async getDailyQuests(userId: string, date: string): Promise<DailyQuestRow[]> {
    return this.dailyQuests.get(`${userId}:${date}`) || []
  }

  async upsertDailyQuest(userId: string, date: string, questId: string): Promise<void> {
    const key = `${userId}:${date}`
    const rows = this.dailyQuests.get(key) || []
    if (!rows.some((r) => r.quest_id === questId)) {
      rows.push({ quest_id: questId, completed: false, stars_earned: 0 })
    }
    this.dailyQuests.set(key, rows)
  }

  async completeDailyQuest(
    userId: string,
    date: string,
    questId: string,
    stars_earned: number
  ): Promise<{ success: boolean; alreadyCompleted: boolean }> {
    const key = `${userId}:${date}`
    const rows = this.dailyQuests.get(key) || []
    const row = rows.find((r) => r.quest_id === questId)
    if (row?.completed) return { success: false, alreadyCompleted: true }

    if (row) {
      row.completed = true
      row.stars_earned = stars_earned
    } else {
      rows.push({ quest_id: questId, completed: true, stars_earned })
    }
    this.dailyQuests.set(key, rows)
    return { success: true, alreadyCompleted: false }
  }

  async cleanupOldDailyQuests(_userId: string, _beforeDate: string): Promise<void> {
    // No-op for memory storage
  }

  /** For testing: clear all state */
  clear(): void {
    this.questCompletions.clear()
    this.userStats.clear()
    this.dailyQuests.clear()
  }
}
