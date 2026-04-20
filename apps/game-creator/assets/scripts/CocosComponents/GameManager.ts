/**
 * GameManager - Top-level game controller, attached to the root Canvas node.
 * Initializes CCGlobalState, handles scene transitions, and manages game lifecycle.
 */

import { _decorator, Component, Node, director } from 'cc'
import { CCGlobalState } from '../Integration/CCGlobalState'

const { ccclass, property } = _decorator

@ccclass('GameManager')
export class GameManager extends Component {
  @property(Node) uiLayer: Node | null = null
  @property(Node) worldLayer: Node | null = null
  @property(Node) hudNode: Node | null = null

  start() {
    // Initialize global state
    const state = CCGlobalState.getInstance()
    const world = state.gameWorld

    console.log('[GameManager] Game started, LXP:', world.getStoryProgress().total_lxp)

    // Emit game ready event for other components to listen to
    this.node.emit('game_ready')
  }

  /**
   * Transition to a new game scene.
   */
  async enterGameScene(sceneId: string): Promise<void> {
    const state = CCGlobalState.getInstance()
    const world = state.gameWorld

    if (!world.canEnterScene(sceneId)) {
      console.warn(`[GameManager] Scene ${sceneId} is locked`)
      this.node.emit('scene_locked', sceneId)
      return
    }

    await world.enterScene(sceneId)
    this.node.emit('scene_entered', sceneId)
  }

  /**
   * Called when a quest is completed.
   */
  onQuestCompleted(questId: string, earnedLxp: number): void {
    const state = CCGlobalState.getInstance()
    state.gameWorld.advanceStory(questId, earnedLxp)

    this.node.emit('quest_completed', { questId, earnedLxp })

    // Check if current scene's badge should be awarded
    const badges = state.gameWorld.getEarnedBadges()
    if (badges.length === 3) {
      this.node.emit('chapter_complete')
    }
  }
}
