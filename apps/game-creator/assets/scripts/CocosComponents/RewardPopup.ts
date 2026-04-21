/**
 * RewardPopup - Canvas-layer badge/XP popup controller.
 * Wraps the existing RewardShowcaseUI class.
 */

import { _decorator, Component, Node, instantiate, Prefab } from 'cc'
import { RewardShowcaseUI } from '../game-client/ui/RewardShowcaseUI'
import { CCGlobalState } from '../Integration/CCGlobalState'

const { ccclass, property } = _decorator

@ccclass('RewardPopup')
export class RewardPopup extends Component {
  @property(Prefab) popupPrefab: Prefab | null = null

  private rewardUI: RewardShowcaseUI | null = null
  private activeNode: Node | null = null

  start() {
    this.node.on('show_rewards', (data) => {
      this.show(data)
    })

    // Listen for badge unlocks
    this.node.on('badge_unlocked', (data: { badgeId: string }) => {
      this.showBadgeEarned(data.badgeId)
    })

    // Listen for chapter completion
    this.node.on('chapter_complete', () => {
      this.showChapterComplete()
    })
  }

  show(data: { lxp: number; level: number; badges: string[] }): void {
    if (!this.activeNode && this.popupPrefab) {
      this.activeNode = instantiate(this.popupPrefab)
      this.node.addChild(this.activeNode)
      this.rewardUI = new RewardShowcaseUI(this.activeNode)
    }
    this.rewardUI?.showRewards(data.lxp, data.level, data.badges)
  }

  showBadgeEarned(badgeId: string): void {
    const state = CCGlobalState.getInstance()
    const progress = state.gameWorld.getStoryProgress()

    this.show({
      lxp: progress.total_lxp,
      level: 1,
      badges: [badgeId],
    })
  }

  showChapterComplete(): void {
    const state = CCGlobalState.getInstance()
    const progress = state.gameWorld.getStoryProgress()

    this.show({
      lxp: progress.total_lxp,
      level: 1,
      badges: progress.earned_badges,
    })
  }

  hide(): void {
    if (this.activeNode) {
      this.activeNode.destroy()
      this.activeNode = null
      this.rewardUI = null
    }
  }
}
