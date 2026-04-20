/**
 * RewardPopup - Canvas-layer badge/XP popup controller.
 * Wraps the existing RewardShowcaseUI class.
 */

import { _decorator, Component, Node, instantiate, Prefab } from 'cc'
import { RewardShowcaseUI } from '../game-client/ui/RewardShowcaseUI'

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
  }

  show(data: { lxp: number; level: number; badges: string[] }): void {
    if (!this.activeNode && this.popupPrefab) {
      this.activeNode = instantiate(this.popupPrefab)
      this.node.addChild(this.activeNode)
      this.rewardUI = new RewardShowcaseUI(this.activeNode)
    }

    this.rewardUI?.showRewards(data.lxp, data.level, data.badges)
  }

  hide(): void {
    if (this.activeNode) {
      this.activeNode.destroy()
      this.activeNode = null
      this.rewardUI = null
    }
  }
}
