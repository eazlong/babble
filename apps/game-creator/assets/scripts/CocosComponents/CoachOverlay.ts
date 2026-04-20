/**
 * CoachOverlay - Canvas-layer Spark coach overlay.
 * Wraps the existing SpiritCoachUI class.
 */

import { _decorator, Component, Node, instantiate, Prefab } from 'cc'
import { SpiritCoachUI } from '../game-client/ui/SpiritCoachUI'

const { ccclass, property } = _decorator

@ccclass('CoachOverlay')
export class CoachOverlay extends Component {
  @property(Prefab) coachPrefab: Prefab | null = null

  private coachUI: SpiritCoachUI | null = null
  private activeNode: Node | null = null

  start() {
    if (this.coachPrefab) {
      this.activeNode = instantiate(this.coachPrefab)
      this.node.addChild(this.activeNode)
      this.coachUI = new SpiritCoachUI(this.activeNode)
    }
  }

  showHint(hint: string): void {
    this.coachUI?.showHint(hint)
  }

  hideHint(): void {
    this.coachUI?.hideHint()
  }

  showExcited(): void {
    this.coachUI?.showExcited()
  }

  setIdle(): void {
    this.coachUI?.setIdle()
  }
}
