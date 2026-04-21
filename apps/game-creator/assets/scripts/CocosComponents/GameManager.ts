/**
 * GameManager - Central event hub and game controller.
 * Initializes HybridAPI, QuestManager, and coordinates scene lifecycle.
 */

import { _decorator, Component, Node, director, tween, Color, Sprite } from 'cc'
import { CCGlobalState } from '../Integration/CCGlobalState'
import { HybridAPI } from '../Utils/HybridAPI'
import { QuestManager } from '../Utils/QuestManager'

const { ccclass, property } = _decorator

@ccclass('GameManager')
export class GameManager extends Component {
  @property(Node) uiLayer: Node | null = null
  @property(Node) worldLayer: Node | null = null
  @property(Node) hudNode: Node | null = null

  private hybridAPI: HybridAPI | null = null
  private questManager: QuestManager | null = null

  onLoad() {
    this.hybridAPI = new HybridAPI()
    this.questManager = this.node.addComponent(QuestManager)
    this.questManager.init(this.hybridAPI)

    // Wire quest manager events to UI
    this.questManager.node.on('update_quest', (quest) => {
      this.node.emit('update_quest', quest)
    })
    this.questManager.node.on('quest_completed', (data) => {
      this.onQuestCompleted(data.questId, data.lxp, data.stars)
    })
    this.questManager.node.on('badge_unlocked', (data) => {
      this.node.emit('badge_unlocked', data)
    })
  }

  async start() {
    // Check service connectivity
    const online = await this.hybridAPI!.pingServices()
    console.log(`[GameManager] Services ${online ? 'online' : 'offline (using local mode)'}`)

    // Initialize global state
    const state = CCGlobalState.getInstance()
    const world = state.gameWorld
    console.log('[GameManager] Game started, LXP:', world.getStoryProgress().total_lxp)

    // Auto-enter first available scene
    await this.enterGameScene('spirit_forest')

    this.node.emit('game_ready')
  }

  /**
   * Transition to a game scene with fade effect.
   */
  async enterGameScene(sceneId: string): Promise<void> {
    const state = CCGlobalState.getInstance()
    const world = state.gameWorld

    if (!world.canEnterScene(sceneId)) {
      console.warn(`[GameManager] Scene ${sceneId} is locked`)
      this.node.emit('scene_locked', sceneId)
      return
    }

    // Fade out
    await this.fadeToBlack(0.3)

    // Load scene
    await world.enterScene(sceneId)

    // Load quests for this scene
    await this.questManager?.loadSceneQuests(sceneId)

    // Notify other components
    this.node.emit('scene_entered', sceneId)

    // Fade in
    await this.fadeFromBlack(0.3)
  }

  /**
   * Called when a quest is completed.
   */
  onQuestCompleted(questId: string, earnedLxp: number, stars: number): void {
    const state = CCGlobalState.getInstance()
    state.gameWorld.advanceStory(questId, earnedLxp)

    this.node.emit('quest_completed', { questId, earnedLxp, stars })

    // Check if chapter is complete (all 3 badges)
    const badges = state.gameWorld.getEarnedBadges()
    if (badges.length >= 3) {
      this.node.emit('chapter_complete')
    }
  }

  /**
   * Handle badge unlock - notify reward popup.
   */
  onBadgeUnlocked(badgeId: string): void {
    const state = CCGlobalState.getInstance()
    state.gameWorld.addBadge(badgeId)
    this.node.emit('badge_unlocked', { badgeId })
  }

  private fadeToBlack(duration: number): Promise<void> {
    return new Promise((resolve) => {
      // Simple: just wait for now. Real implementation uses a fade overlay node.
      setTimeout(resolve, duration * 1000)
    })
  }

  private fadeFromBlack(duration: number): Promise<void> {
    return new Promise((resolve) => {
      setTimeout(resolve, duration * 1000)
    })
  }
}
