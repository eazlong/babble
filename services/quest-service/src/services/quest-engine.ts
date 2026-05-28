import type { SupabaseClient } from "@supabase/supabase-js"
import { MemoryQuestStorage, type QuestStorage, type UserQuestState } from "./quest-storage.js"
import { getRewardDrop } from "./reward-client.js"

export interface QuestCompletionResult {
  success: boolean
  lxp_earned: number
  accuracy_score: number
  fluency_score: number
  vocabulary_score: number
  stars_earned: number
  badge_unlocked: string | null
  rewards: Array<{ item_id: string; name: string }>
  all_scene_quests_complete: boolean
}

export interface Quest {
  quest_id: string
  title: string
  title_en: string
  description: string
  description_en: string
  quest_type: 'main' | 'sub' | 'daily'
  scene_id: string
  difficulty_level: number
  cefr_requirement: string
  lxp_reward_base: number
  target_language_focus: string[]
  is_active: boolean
  parent_quest_id?: string
}

interface DailyQuestProgress {
  quest_id: string
  completed: boolean
  stars_earned: number
}

// ============================================================
// Chapter 1 Quest Data
// ============================================================

const CHAPTER_1_QUESTS: Quest[] = [
  // --- Spirit Forest (scene: spirit_forest) ---
  {
    quest_id: 'quest_forest_main',
    title: '探索精灵森林',
    title_en: 'Explore the Spirit Forest',
    description: '完成精灵森林中的所有任务',
    description_en: 'Complete all tasks in the Spirit Forest',
    quest_type: 'main',
    scene_id: 'spirit_forest',
    difficulty_level: 1,
    cefr_requirement: 'A1',
    lxp_reward_base: 100,
    target_language_focus: ['greeting', 'colors', 'numbers'],
    is_active: true,
  },
  {
    quest_id: 'greet_oakley',
    title: '问候 Oakley',
    title_en: 'Greet Oakley',
    description: '用英语向森林精灵 Oakley 打招呼',
    description_en: 'Greet Oakley the forest spirit in English',
    quest_type: 'sub',
    scene_id: 'spirit_forest',
    difficulty_level: 1,
    cefr_requirement: 'A1',
    lxp_reward_base: 30,
    target_language_focus: ['greeting', 'introductions'],
    is_active: true,
    parent_quest_id: 'quest_forest_main',
  },
  {
    quest_id: 'activate_flowers',
    title: '激活花朵',
    title_en: 'Activate the Flowers',
    description: '用颜色魔法激活森林中的花朵',
    description_en: 'Use color magic to activate the flowers in the forest',
    quest_type: 'sub',
    scene_id: 'spirit_forest',
    difficulty_level: 1,
    cefr_requirement: 'A1',
    lxp_reward_base: 35,
    target_language_focus: ['colors', 'adjectives'],
    is_active: true,
    parent_quest_id: 'quest_forest_main',
  },
  {
    quest_id: 'open_chest',
    title: '打开宝箱',
    title_en: 'Open the Treasure Chest',
    description: '用数字魔法打开森林宝箱',
    description_en: 'Use number magic to open the forest treasure chest',
    quest_type: 'sub',
    scene_id: 'spirit_forest',
    difficulty_level: 1,
    cefr_requirement: 'A1',
    lxp_reward_base: 35,
    target_language_focus: ['numbers', 'counting'],
    is_active: true,
    parent_quest_id: 'quest_forest_main',
  },

  // --- Spell Library (scene: spell_library) ---
  {
    quest_id: 'quest_library_main',
    title: '探索咒语图书馆',
    title_en: 'Explore the Spell Library',
    description: '完成咒语图书馆中的所有任务',
    description_en: 'Complete all tasks in the Spell Library',
    quest_type: 'main',
    scene_id: 'spell_library',
    difficulty_level: 1,
    cefr_requirement: 'A1',
    lxp_reward_base: 100,
    target_language_focus: ['classroom', 'instructions', 'reading'],
    is_active: true,
  },
  {
    quest_id: 'organize_books',
    title: '整理魔法书',
    title_en: 'Organize the Magic Books',
    description: '按颜色和大小整理魔法书籍',
    description_en: 'Organize the magic books by color and size',
    quest_type: 'sub',
    scene_id: 'spell_library',
    difficulty_level: 1,
    cefr_requirement: 'A1',
    lxp_reward_base: 30,
    target_language_focus: ['colors', 'sizes', 'adjectives'],
    is_active: true,
    parent_quest_id: 'quest_library_main',
  },
  {
    quest_id: 'follow_commands',
    title: '执行课堂指令',
    title_en: 'Follow Classroom Commands',
    description: '听从老师指令完成课堂任务',
    description_en: 'Follow teacher commands to complete classroom tasks',
    quest_type: 'sub',
    scene_id: 'spell_library',
    difficulty_level: 1,
    cefr_requirement: 'A1',
    lxp_reward_base: 35,
    target_language_focus: ['instructions', 'actions', 'classroom'],
    is_active: true,
    parent_quest_id: 'quest_library_main',
  },
  {
    quest_id: 'practice_dialogue',
    title: '与 Luna 对话练习',
    title_en: 'Practice Dialogue with Luna',
    description: '和 Luna 进行英语对话练习',
    description_en: 'Practice English conversation with Luna',
    quest_type: 'sub',
    scene_id: 'spell_library',
    difficulty_level: 1,
    cefr_requirement: 'A1',
    lxp_reward_base: 35,
    target_language_focus: ['dialogue', 'questions', 'answers'],
    is_active: true,
    parent_quest_id: 'quest_library_main',
  },

  // --- Rainbow Garden (scene: rainbow_garden) ---
  {
    quest_id: 'quest_garden_main',
    title: '探索彩虹花园',
    title_en: 'Explore the Rainbow Garden',
    description: '完成彩虹花园中的所有任务',
    description_en: 'Complete all tasks in the Rainbow Garden',
    quest_type: 'main',
    scene_id: 'rainbow_garden',
    difficulty_level: 1,
    cefr_requirement: 'A1',
    lxp_reward_base: 100,
    target_language_focus: ['animals', 'weather', 'nature'],
    is_active: true,
  },
  {
    quest_id: 'fix_weather_crystal',
    title: '修复天气水晶',
    title_en: 'Fix the Weather Crystal',
    description: '修复花园中的天气水晶',
    description_en: 'Repair the weather crystal in the garden',
    quest_type: 'sub',
    scene_id: 'rainbow_garden',
    difficulty_level: 1,
    cefr_requirement: 'A1',
    lxp_reward_base: 30,
    target_language_focus: ['weather', 'seasons'],
    is_active: true,
    parent_quest_id: 'quest_garden_main',
  },
  {
    quest_id: 'find_lost_animals',
    title: '找到迷路小动物',
    title_en: 'Find the Lost Animals',
    description: '在花园中找到迷路的小动物',
    description_en: 'Find the lost little animals in the garden',
    quest_type: 'sub',
    scene_id: 'rainbow_garden',
    difficulty_level: 1,
    cefr_requirement: 'A1',
    lxp_reward_base: 35,
    target_language_focus: ['animals', 'locations', 'directions'],
    is_active: true,
    parent_quest_id: 'quest_garden_main',
  },
  {
    quest_id: 'plant_flowers',
    title: '种植魔法花朵',
    title_en: 'Plant Magic Flowers',
    description: '在花园中种植魔法花朵',
    description_en: 'Plant magic flowers in the garden',
    quest_type: 'sub',
    scene_id: 'rainbow_garden',
    difficulty_level: 1,
    cefr_requirement: 'A1',
    lxp_reward_base: 35,
    target_language_focus: ['nature', 'colors', 'verbs'],
    is_active: true,
    parent_quest_id: 'quest_garden_main',
  },
]

// ============================================================
// Daily Quest Pool — rotating selection for daily quests
// ============================================================

const DAILY_QUEST_POOL: Quest[] = [
  {
    quest_id: 'daily_greet',
    title: '向3位NPC打招呼',
    title_en: 'Greet 3 NPCs',
    description: '练习问候用语',
    description_en: 'Practice greeting phrases with different characters',
    quest_type: 'daily',
    scene_id: 'spirit_forest',
    difficulty_level: 1,
    cefr_requirement: 'A1',
    lxp_reward_base: 20,
    target_language_focus: ['greeting'],
    is_active: true,
  },
  {
    quest_id: 'daily_colors',
    title: '收集3种颜色',
    title_en: 'Collect 3 Colors',
    description: '用英语说出3种不同的颜色',
    description_en: 'Name 3 different colors in English',
    quest_type: 'daily',
    scene_id: 'spirit_forest',
    difficulty_level: 1,
    cefr_requirement: 'A1',
    lxp_reward_base: 20,
    target_language_focus: ['colors'],
    is_active: true,
  },
  {
    quest_id: 'daily_numbers',
    title: '数到10',
    title_en: 'Count to 10',
    description: '用英语从1数到10',
    description_en: 'Count from 1 to 10 in English',
    quest_type: 'daily',
    scene_id: 'spirit_forest',
    difficulty_level: 1,
    cefr_requirement: 'A1',
    lxp_reward_base: 20,
    target_language_focus: ['numbers', 'counting'],
    is_active: true,
  },
  {
    quest_id: 'daily_books',
    title: '整理5本魔法书',
    title_en: 'Organize 5 Magic Books',
    description: '按颜色或大小整理魔法书',
    description_en: 'Sort magic books by color or size',
    quest_type: 'daily',
    scene_id: 'spell_library',
    difficulty_level: 1,
    cefr_requirement: 'A1',
    lxp_reward_base: 20,
    target_language_focus: ['colors', 'sizes'],
    is_active: true,
  },
  {
    quest_id: 'daily_commands',
    title: '完成3个课堂指令',
    title_en: 'Complete 3 Classroom Commands',
    description: '听从老师的课堂指令',
    description_en: 'Follow teacher commands in the classroom',
    quest_type: 'daily',
    scene_id: 'spell_library',
    difficulty_level: 1,
    cefr_requirement: 'A1',
    lxp_reward_base: 20,
    target_language_focus: ['instructions', 'actions'],
    is_active: true,
  },
  {
    quest_id: 'daily_dialogue',
    title: '和NPC进行一次对话',
    title_en: 'Have a Dialogue with an NPC',
    description: '与任意NPC进行至少3轮对话',
    description_en: 'Have at least 3 rounds of dialogue with any NPC',
    quest_type: 'daily',
    scene_id: 'spell_library',
    difficulty_level: 1,
    cefr_requirement: 'A1',
    lxp_reward_base: 25,
    target_language_focus: ['dialogue', 'questions'],
    is_active: true,
  },
  {
    quest_id: 'daily_flowers',
    title: '种下2朵魔法花',
    title_en: 'Plant 2 Magic Flowers',
    description: '在彩虹花园种下花朵',
    description_en: 'Plant flowers in the rainbow garden',
    quest_type: 'daily',
    scene_id: 'rainbow_garden',
    difficulty_level: 1,
    cefr_requirement: 'A1',
    lxp_reward_base: 20,
    target_language_focus: ['nature', 'colors'],
    is_active: true,
  },
  {
    quest_id: 'daily_animals',
    title: '找到1只迷路的小动物',
    title_en: 'Find 1 Lost Animal',
    description: '在花园中找到迷路的小动物',
    description_en: 'Find a lost little animal in the garden',
    quest_type: 'daily',
    scene_id: 'rainbow_garden',
    difficulty_level: 1,
    cefr_requirement: 'A1',
    lxp_reward_base: 20,
    target_language_focus: ['animals'],
    is_active: true,
  },
  {
    quest_id: 'daily_weather',
    title: '修复天气水晶',
    title_en: 'Fix the Weather Crystal',
    description: '用英语说出2种天气',
    description_en: 'Name 2 types of weather in English',
    quest_type: 'daily',
    scene_id: 'rainbow_garden',
    difficulty_level: 1,
    cefr_requirement: 'A1',
    lxp_reward_base: 20,
    target_language_focus: ['weather', 'seasons'],
    is_active: true,
  },
  {
    quest_id: 'daily_shop',
    title: '在集市购买一件物品',
    title_en: 'Buy an Item at the Market',
    description: '用目标语言询价并购买',
    description_en: 'Ask price and buy an item in target language',
    quest_type: 'daily',
    scene_id: 'any',
    difficulty_level: 1,
    cefr_requirement: 'A1',
    lxp_reward_base: 20,
    target_language_focus: ['shopping', 'numbers'],
    is_active: true,
  },
  {
    quest_id: 'daily_directions',
    title: '询问一个地点的方向',
    title_en: 'Ask for Directions to a Location',
    description: '用英语询问并理解方向',
    description_en: 'Ask and understand directions in English',
    quest_type: 'daily',
    scene_id: 'any',
    difficulty_level: 1,
    cefr_requirement: 'A1',
    lxp_reward_base: 20,
    target_language_focus: ['directions', 'locations'],
    is_active: true,
  },
  {
    quest_id: 'daily_introduce',
    title: '自我介绍你的名字和年龄',
    title_en: 'Introduce Your Name and Age',
    description: '用英语介绍自己的名字和年龄',
    description_en: 'Introduce yourself with name and age in English',
    quest_type: 'daily',
    scene_id: 'spirit_forest',
    difficulty_level: 1,
    cefr_requirement: 'A1',
    lxp_reward_base: 25,
    target_language_focus: ['introductions', 'numbers'],
    is_active: true,
  },
]

const DAILY_QUESTS_PER_DAY = 3

// Badge definitions: one per scene, unlocked when all sub-quests complete
const SCENE_BADGES: Record<string, { badge_id: string; name: string; name_en: string }> = {
  spirit_forest: {
    badge_id: 'badge_spirit_forest',
    name: '精灵森林探索者',
    name_en: 'Spirit Forest Explorer',
  },
  spell_library: {
    badge_id: 'badge_spell_library',
    name: '咒语图书馆学者',
    name_en: 'Spell Library Scholar',
  },
  rainbow_garden: {
    badge_id: 'badge_rainbow_garden',
    name: '彩虹花园守护者',
    name_en: 'Rainbow Garden Guardian',
  },
}

// ============================================================
// Helper functions
// ============================================================

function calculateStars(scores: { accuracy: number; fluency: number; vocabulary: number }): number {
  const avg = (scores.accuracy + scores.fluency + scores.vocabulary) / 3
  if (avg >= 90) return 3
  if (avg >= 70) return 2
  if (avg >= 40) return 1
  return 0
}

function getSubQuestsInScene(sceneId: string): Quest[] {
  return CHAPTER_1_QUESTS.filter(
    (q) => q.scene_id === sceneId && q.quest_type === 'sub'
  )
}

function checkSceneBadgeCompletion(
  sceneId: string,
  state: UserQuestState
): string | null {
  const subQuestsInScene = getSubQuestsInScene(sceneId)
  const allComplete = subQuestsInScene.every((q) => state.completed_sub_quests.has(q.quest_id))
  if (!allComplete) return null

  const badge = SCENE_BADGES[sceneId]
  if (!badge) return null
  if (state.badges.has(badge.badge_id)) return null // already unlocked

  state.badges.add(badge.badge_id)
  state.scene_badges.add(badge.badge_id)
  return badge.badge_id
}

function makeEmptyResult(): QuestCompletionResult {
  return {
    success: false,
    lxp_earned: 0,
    accuracy_score: 0,
    fluency_score: 0,
    vocabulary_score: 0,
    stars_earned: 0,
    badge_unlocked: null,
    rewards: [],
    all_scene_quests_complete: false,
  }
}

function makeResult(
  success: boolean,
  scores: { accuracy: number; fluency: number; vocabulary: number },
  lxp: number,
  stars: number,
  badge: string | null,
  rewards: Array<{ item_id: string; name: string }>,
  allSceneComplete: boolean
): QuestCompletionResult {
  return {
    success,
    lxp_earned: lxp,
    accuracy_score: scores.accuracy,
    fluency_score: scores.fluency,
    vocabulary_score: scores.vocabulary,
    stars_earned: stars,
    badge_unlocked: badge,
    rewards,
    all_scene_quests_complete: allSceneComplete,
  }
}

// ============================================================
// Quest Engine
// ============================================================

export class QuestEngine {
  private storage: QuestStorage

  constructor(storage?: QuestStorage) {
    this.storage = storage || new MemoryQuestStorage()
  }

  async getUserQuests(userId: string, sceneId?: string): Promise<Quest[]> {
    let quests = CHAPTER_1_QUESTS.filter((q) => q.is_active)
    if (sceneId) {
      quests = quests.filter((q) => q.scene_id === sceneId)
    }
    return quests
  }

  async completeQuest(
    userId: string,
    questId: string,
    scores: { accuracy: number; fluency: number; vocabulary: number }
  ): Promise<QuestCompletionResult> {
    const quest = CHAPTER_1_QUESTS.find((q) => q.quest_id === questId)
    if (!quest) return makeEmptyResult()

    const state = await this.storage.loadUserState(userId)
    // Rebuild completed_sub_quests from stored completed_quest_ids
    for (const qid of state.completed_quest_ids) {
      const q = CHAPTER_1_QUESTS.find((x) => x.quest_id === qid)
      if (q?.quest_type === 'sub') state.completed_sub_quests.add(qid)
    }

    // Idempotent: check if already completed (cached result from storage)
    const cached = state.quest_results.get(questId)
    if (cached) {
      const subQuestsInScene = getSubQuestsInScene(quest.scene_id)
      const allComplete = subQuestsInScene.every((q) => state.completed_sub_quests.has(q.quest_id))
      return { ...cached, all_scene_quests_complete: allComplete }
    }

    // Calculate LXP = accuracy*0.4 + fluency*0.3 + vocabulary*0.3
    const lxp = Math.round(
      scores.accuracy * 0.4 + scores.fluency * 0.3 + scores.vocabulary * 0.3
    )

    // Calculate stars
    const stars = calculateStars(scores)
    state.total_stars += stars

    // Track sub-quest completion
    if (quest.quest_type === 'sub') {
      state.completed_sub_quests.add(questId)
    }

    // Check badge unlock
    const badge = checkSceneBadgeCompletion(quest.scene_id, state)

    // Check scene completion
    const subQuestsInScene = getSubQuestsInScene(quest.scene_id)
    const allSceneComplete = subQuestsInScene.every((q) => state.completed_sub_quests.has(q.quest_id))

    const rewards = await this.calculateRewards(questId, quest.quest_type, quest.cefr_requirement)

    // Persist to storage
    await this.storage.completeQuest(
      userId, questId, quest.scene_id, scores,
      lxp, stars, badge, rewards
    )

    state.completed_quest_ids.add(questId)
    await this.storage.updateUserStats(userId, state.total_stars, Array.from(state.badges))

    return makeResult(true, scores, lxp, stars, badge, rewards, allSceneComplete)
  }

  async generateDailyQuests(userId: string): Promise<Quest[]> {
    return this.getDailyQuests(userId)
  }

  async getUserStars(userId: string): Promise<number> {
    const state = await this.storage.loadUserState(userId)
    return state.total_stars
  }

  async getUserBadges(userId: string): Promise<string[]> {
    const state = await this.storage.loadUserState(userId)
    return Array.from(state.badges)
  }

  getDailyQuests(userId: string): Quest[] {
    const today = new Date().toISOString().slice(0, 10)
    const seed = today.split('-').join('')
    const pool = [...DAILY_QUEST_POOL]
    for (let i = pool.length - 1; i > 0; i--) {
      const j = (Math.floor(parseInt(seed.slice(0, 8)) * (i + 1) * 9301 + 49297) % 233280) % (i + 1)
      const swap = pool[i]
      pool[i] = pool[j]!
      pool[j] = swap
    }
    return pool.slice(0, DAILY_QUESTS_PER_DAY)
  }

  async completeDailyQuest(
    userId: string,
    questId: string,
    scores: { accuracy: number; fluency: number; vocabulary: number }
  ): Promise<{ success: boolean; message: string }> {
    const quest = DAILY_QUEST_POOL.find((q) => q.quest_id === questId)
    if (!quest) return { success: false, message: 'Quest not found' }

    const state = await this.storage.loadUserState(userId)
    const today = state.daily_quest_date || new Date().toISOString().slice(0, 10)

    const existing = state.daily_quest_progress.get(questId)
    if (existing?.completed) {
      return { success: false, message: 'Already completed' }
    }

    const stars = calculateStars(scores)
    state.total_stars += stars

    // Persist
    const result = await this.storage.completeDailyQuest(userId, today, questId, stars)
    if (result.alreadyCompleted) {
      return { success: false, message: 'Already completed' }
    }

    await this.storage.updateUserStats(userId, state.total_stars, Array.from(state.badges))

    // Also mark in local state
    state.daily_quest_progress.set(questId, {
      quest_id: questId,
      completed: true,
      stars_earned: stars,
    })
    state.completed_quest_ids.add(questId)

    return { success: true, message: 'Daily quest completed' }
  }

  async reportQuestCompletion(
    userId: string,
    questId: string,
    sceneId: string,
    scores: { accuracy: number; fluency: number; vocabulary: number },
    playerInput?: string
  ): Promise<QuestCompletionResult & { all_scene_quests_complete: boolean }> {
    const quest = CHAPTER_1_QUESTS.find((q) => q.quest_id === questId)
    if (!quest) return { ...makeEmptyResult(), all_scene_quests_complete: false }

    const state = await this.storage.loadUserState(userId)

    // Rebuild completed_sub_quests from stored completed_quest_ids
    for (const qid of state.completed_quest_ids) {
      const q = CHAPTER_1_QUESTS.find((x) => x.quest_id === qid)
      if (q?.quest_type === 'sub') state.completed_sub_quests.add(qid)
    }

    // Idempotent: check cached result
    const cached = state.quest_results.get(questId)
    if (cached) {
      const subQuestsInScene = getSubQuestsInScene(sceneId)
      const allComplete = subQuestsInScene.every((q) => state.completed_sub_quests.has(q.quest_id))
      return { ...cached, all_scene_quests_complete: allComplete }
    }

    // Calculate LXP
    const lxp = Math.round(
      scores.accuracy * 0.4 + scores.fluency * 0.3 + scores.vocabulary * 0.3
    )

    // Calculate stars
    const stars = calculateStars(scores)
    state.total_stars += stars

    // Mark completed
    state.completed_quest_ids.add(questId)

    // Track sub-quest
    if (quest.quest_type === 'sub') {
      state.completed_sub_quests.add(questId)
    }

    // Badge check
    const badge = checkSceneBadgeCompletion(quest.scene_id, state)

    // Scene completion check
    const subQuestsInScene = getSubQuestsInScene(sceneId)
    const allSceneComplete = subQuestsInScene.every((q) => state.completed_sub_quests.has(q.quest_id))

    const rewards = await this.calculateRewards(questId, quest.quest_type, quest.cefr_requirement)

    // Persist
    await this.storage.completeQuest(
      userId, questId, quest.scene_id, scores,
      lxp, stars, badge, rewards
    )
    await this.storage.updateUserStats(userId, state.total_stars, Array.from(state.badges))

    return makeResult(true, scores, lxp, stars, badge, rewards, allSceneComplete)
  }

  async getQuestStatus(
    userId: string,
    sceneId: string
  ): Promise<{
    scene_id: string
    completed_quest_ids: string[]
    pending_quest_ids: string[]
    badge_unlocked: boolean
    total_stars: number
  }> {
    const state = await this.storage.loadUserState(userId)
    // Rebuild completed_sub_quests from stored completed_quest_ids
    for (const qid of state.completed_quest_ids) {
      const q = CHAPTER_1_QUESTS.find((x) => x.quest_id === qid)
      if (q?.quest_type === 'sub') state.completed_sub_quests.add(qid)
    }

    const questsInScene = CHAPTER_1_QUESTS.filter(
      (q) => q.scene_id === sceneId && q.is_active
    )

    const completedIds = questsInScene
      .filter((q) => state.completed_quest_ids.has(q.quest_id))
      .map((q) => q.quest_id)

    const pendingIds = questsInScene
      .filter((q) => !state.completed_quest_ids.has(q.quest_id))
      .map((q) => q.quest_id)

    const badge = SCENE_BADGES[sceneId]
    const badgeUnlocked = badge ? state.badges.has(badge.badge_id) : false

    return {
      scene_id: sceneId,
      completed_quest_ids: completedIds,
      pending_quest_ids: pendingIds,
      badge_unlocked: badgeUnlocked,
      total_stars: state.total_stars,
    }
  }

  private async calculateRewards(questId: string, questType: string = "sub", cefr: string = "A1"): Promise<Array<{ item_id: string; name: string }>> {
    return getRewardDrop(questType as any, cefr)
  }
}
