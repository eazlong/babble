/**
 * NPCController - Attached to each NPC prefab. Handles idle animation,
 * tap-to-interact, and dialogue triggering.
 */

import { _decorator, Component, Node, tween, Vec3 } from 'cc'
import { CCGlobalState } from '../Integration/CCGlobalState'

const { ccclass, property } = _decorator

@ccclass('NPCController')
export class NPCController extends Component {
  @property({ tooltip: 'NPC identifier matching the database' })
  npcId: string = ''

  @property({ tooltip: 'Dialogue session ID' })
  sessionId: string = ''

  @property(Node) indicatorNode: Node | null = null

  private isInteracting: boolean = false

  start() {
    // Show interaction indicator by default (exclamation mark)
    if (this.indicatorNode) {
      this.indicatorNode.active = true
      this.animateIndicator()
    }

    // Tap to interact
    this.node.on(Node.EventType.TOUCH_END, this.onTap, this)
  }

  async onTap(): Promise<void> {
    if (this.isInteracting || !this.npcId) return
    this.isInteracting = true

    // Hide indicator
    if (this.indicatorNode) {
      this.indicatorNode.active = false
    }

    // Notify GameManager to start dialogue with this NPC
    this.node.emit('npc_interaction_started', {
      npcId: this.npcId,
      sessionId: this.sessionId,
    })

    // Interaction complete after dialogue system takes over
    this.isInteracting = false
  }

  /**
   * Called when dialogue with this NPC is complete.
   */
  onDialogueComplete(): void {
    if (this.indicatorNode) {
      this.indicatorNode.active = true
      this.animateIndicator()
    }
  }

  private animateIndicator(): void {
    if (!this.indicatorNode) return
    tween(this.indicatorNode)
      .by(0.5, { position: new Vec3(0, 5, 0) })
      .by(0.5, { position: new Vec3(0, -5, 0) })
      .union()
      .repeatForever()
      .start()
  }
}
