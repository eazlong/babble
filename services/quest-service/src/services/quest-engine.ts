export interface QuestCompletionResult {
  success: boolean
  lxp_earned: number
  accuracy_score: number
  fluency_score: number
  vocabulary_score: number
  stars_earned: number
  badge_unlocked: string | null
  rewards: Array<{ item_id: string; name: string }>
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

interface QuestState {
  completed_sub_quests: Set<string>
  total_stars: number
  badges: Set<string>
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
// Quest Engine
// ============================================================

const userStates = new Map<string, QuestState>()

function getUserState(userId: string): QuestState {
  if (!userStates.has(userId)) {
    userStates.set(userId, {
      completed_sub_quests: new Set(),
      total_stars: 0,
      badges: new Set(),
    })
  }
  return userStates.get(userId)!
}

function calculateStars(scores: { accuracy: number; fluency: number; vocabulary: number }): number {
  const avg = (scores.accuracy + scores.fluency + scores.vocabulary) / 3
  if (avg >= 90) return 3
  if (avg >= 70) return 2
  if (avg >= 40) return 1
  return 0
}

function checkSceneBadgeCompletion(
  userId: string,
  sceneId: string,
  state: QuestState
): string | null {
  const subQuestsInScene = CHAPTER_1_QUESTS.filter(
    (q) => q.scene_id === sceneId && q.quest_type === 'sub'
  )
  const allComplete = subQuestsInScene.every((q) => state.completed_sub_quests.has(q.quest_id))
  if (!allComplete) return null

  const badge = SCENE_BADGES[sceneId]
  if (!badge) return null
  if (state.badges.has(badge.badge_id)) return null // already unlocked

  state.badges.add(badge.badge_id)
  return badge.badge_id
}

export class QuestEngine {
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
    if (!quest) {
      return {
        success: false,
        lxp_earned: 0,
        accuracy_score: scores.accuracy,
        fluency_score: scores.fluency,
        vocabulary_score: scores.vocabulary,
        stars_earned: 0,
        badge_unlocked: null,
        rewards: [],
      }
    }

    const state = getUserState(userId)

    // Calculate LXP based on scores
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

    // Check if completing this sub-quest unlocks a scene badge
    const badge = checkSceneBadgeCompletion(userId, quest.scene_id, state)

    const rewards = await this.calculateRewards(questId)

    return {
      success: true,
      lxp_earned: lxp,
      accuracy_score: scores.accuracy,
      fluency_score: scores.fluency,
      vocabulary_score: scores.vocabulary,
      stars_earned: stars,
      badge_unlocked: badge,
      rewards,
    }
  }

  async generateDailyQuests(userId: string): Promise<Quest[]> {
    const fallbacks: Quest[] = [
      {
        quest_id: 'daily_greet',
        title: '用目标语言向3个人打招呼',
        title_en: 'Greet 3 People in Target Language',
        description: '练习问候用语',
        description_en: 'Practice greeting phrases',
        quest_type: 'daily',
        scene_id: 'any',
        difficulty_level: 1,
        cefr_requirement: 'A1',
        lxp_reward_base: 20,
        target_language_focus: ['greeting'],
        is_active: true,
      },
      {
        quest_id: 'daily_shop',
        title: '在集市购买一件物品并用目标语言询价',
        title_en: 'Buy an Item at the Market and Ask Price in Target Language',
        description: '练习购物对话',
        description_en: 'Practice shopping dialogue',
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
        title: '询问并理解一个地点的方向',
        title_en: 'Ask and Understand Directions to a Location',
        description: '练习方向表达',
        description_en: 'Practice giving and receiving directions',
        quest_type: 'daily',
        scene_id: 'any',
        difficulty_level: 1,
        cefr_requirement: 'A1',
        lxp_reward_base: 20,
        target_language_focus: ['directions', 'locations'],
        is_active: true,
      },
    ]

    return fallbacks
  }

  /**
   * Get the total stars earned by a user across all quest completions.
   */
  async getUserStars(userId: string): Promise<number> {
    return getUserState(userId).total_stars
  }

  /**
   * Get all badges unlocked by a user.
   */
  async getUserBadges(userId: string): Promise<string[]> {
    return Array.from(getUserState(userId).badges)
  }

  private async calculateRewards(questId: string): Promise<Array<{ item_id: string; name: string }>> {
    // MVP: Always return a reward
    const roll = Math.random() * 100
    if (roll < 80) {
      return [{ item_id: 'item_common_1', name: '铜币' }]
    }
    return []
  }
}
