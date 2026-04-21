/**
 * QuestManager - Coordinates quest loading, completion tracking, and badge unlocking.
 * Bridges HybridAPI data with CocosCreator UI components.
 */

import { _decorator, Component } from 'cc'
import { HybridAPI } from '../Utils/HybridAPI'

const { ccclass } = _decorator

interface QuestProgress {
  quest_id: string
  title: string
  title_en: string
  description: string
  progress: number
  total: number
  completed: boolean
  reward_lxp: number
  star_rating: number
  sub_quests?: Array<{ sub_quest_id: string; title: string; title_en: string; completed: boolean }>
}

@ccclass('QuestManager')
export class QuestManager extends Component {
  private hybridAPI: HybridAPI | null = null
  private currentSceneId: string = ''
  private quests: QuestProgress[] = []
  private completedQuestIds: Set<string> = new Set()

  init(hybridAPI: HybridAPI) {
    this.hybridAPI = hybridAPI
  }

  /** Load quests for a scene and emit display events */
  async loadSceneQuests(sceneId: string): Promise<void> {
    if (!this.hybridAPI) return
    this.currentSceneId = sceneId

    const questData = await this.hybridAPI.getSceneQuests(sceneId)
    if (questData.length === 0) return

    // Group sub-quests under main quests
    const mainQuests = questData.filter((q) => q.quest_type === 'main')
    const subQuests = questData.filter((q) => q.quest_type === 'sub')

    this.quests = mainQuests.map((main) => {
      const subs = subQuests.filter((s) => s.parent_quest_id === main.quest_id)
      const completedCount = subs.filter((s) => this.completedQuestIds.has(s.quest_id)).length

      return {
        quest_id: main.quest_id,
        title: main.title,
        title_en: main.title_en,
        description: main.description,
        progress: completedCount,
        total: subs.length,
        completed: completedCount === subs.length,
        reward_lxp: main.lxp_reward_base,
        star_rating: 0,
        sub_quests: subs.map((s) => ({
          sub_quest_id: s.quest_id,
          title: s.title,
          title_en: s.title_en,
          completed: this.completedQuestIds.has(s.quest_id),
        })),
      }
    })

    // Emit quest display events for UI
    for (const quest of this.quests) {
      this.node.emit('update_quest', quest)
    }
  }

  /** Mark a sub-quest as completed and update progress */
  async completeQuest(questId: string): Promise<{ lxp: number; stars: number; badge: string | null }> {
    if (!this.hybridAPI || this.completedQuestIds.has(questId)) {
      return { lxp: 0, stars: 0, badge: null }
    }

    const result = await this.hybridAPI.completeQuest(questId, {
      accuracy: 80,
      fluency: 70,
      vocabulary: 75,
    })

    this.completedQuestIds.add(questId)

    // Update quest progress display
    await this.loadSceneQuests(this.currentSceneId)

    // Check if badge unlocked
    if (result.badge_unlocked) {
      this.node.emit('badge_unlocked', { badgeId: result.badge_unlocked })
    }

    this.node.emit('quest_completed', { questId, lxp: result.lxp_earned, stars: result.stars_earned })

    return { lxp: result.lxp_earned, stars: result.stars_earned, badge: result.badge_unlocked }
  }

  /** Get the current active quest (first incomplete sub-quest) */
  getActiveQuest(): QuestProgress | null {
    for (const quest of this.quests) {
      if (!quest.completed) return quest
    }
    return null
  }

  getCompletedCount(): number {
    return this.completedQuestIds.size
  }
}
