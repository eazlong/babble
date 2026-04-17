export interface QuestCompletionResult {
  success: boolean
  lxp_earned: number
  accuracy_score: number
  fluency_score: number
  vocabulary_score: number
  rewards: Array<{ item_id: string; name: string }>
}

export interface Quest {
  quest_id: string
  title: string
  description: string
  quest_type: 'main' | 'side' | 'daily'
  scene_id?: string
  difficulty_level: number
  cefr_requirement: string
  lxp_reward_base: number
  target_language_focus: string[]
  is_active: boolean
}

export class QuestEngine {
  async getUserQuests(userId: string, sceneId?: string): Promise<Quest[]> {
    // MVP: Return hardcoded quests
    const quests: Quest[] = [
      {
        quest_id: 'quest_1',
        title: '集市购物',
        description: '在集市购买一件物品',
        quest_type: 'main',
        difficulty_level: 1,
        cefr_requirement: 'A1',
        lxp_reward_base: 50,
        target_language_focus: ['shopping', 'numbers'],
        is_active: true
      }
    ]

    if (sceneId) {
      return quests // In production, filter by scene
    }

    return quests
  }

  async completeQuest(
    userId: string,
    questId: string,
    scores: { accuracy: number; fluency: number; vocabulary: number }
  ): Promise<QuestCompletionResult> {
    const lxp = Math.round(
      scores.accuracy * 0.4 +
      scores.fluency * 0.3 +
      scores.vocabulary * 0.3
    )

    const rewards = await this.calculateRewards(questId)

    return {
      success: true,
      lxp_earned: lxp,
      accuracy_score: scores.accuracy,
      fluency_score: scores.fluency,
      vocabulary_score: scores.vocabulary,
      rewards
    }
  }

  private async calculateRewards(questId: string): Promise<Array<{ item_id: string; name: string }>> {
    // MVP: Always return a reward
    const roll = Math.random() * 100
    if (roll < 80) {
      return [{ item_id: 'item_common_1', name: '铜币' }]
    }
    return []
  }

  async generateDailyQuests(userId: string): Promise<Quest[]> {
    const fallbacks: Quest[] = [
      {
        quest_id: 'daily_greet',
        title: '用目标语言向3个人打招呼',
        description: '练习问候用语',
        quest_type: 'daily',
        difficulty_level: 1,
        cefr_requirement: 'A1',
        lxp_reward_base: 20,
        target_language_focus: ['greeting'],
        is_active: true
      },
      {
        quest_id: 'daily_shop',
        title: '在集市购买一件物品并用目标语言询价',
        description: '练习购物对话',
        quest_type: 'daily',
        difficulty_level: 1,
        cefr_requirement: 'A1',
        lxp_reward_base: 20,
        target_language_focus: ['shopping', 'numbers'],
        is_active: true
      },
      {
        quest_id: 'daily_directions',
        title: '询问并理解一个地点的方向',
        description: '练习方向表达',
        quest_type: 'daily',
        difficulty_level: 1,
        cefr_requirement: 'A1',
        lxp_reward_base: 20,
        target_language_focus: ['directions', 'locations'],
        is_active: true
      }
    ]

    return fallbacks
  }
}
