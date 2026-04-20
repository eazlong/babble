/**
 * PlayerController - Handles tap-to-move movement and collision with interactive zones.
 */

import { _decorator, Component, Node, tween, Vec3, EventTouch } from 'cc'

const { ccclass, property } = _decorator

@ccclass('PlayerController')
export class PlayerController extends Component {
  @property({ tooltip: 'Movement speed in pixels per second' })
  moveSpeed: number = 200

  @property({ tooltip: 'World layer node boundary' })
  worldBounds: Node | null = null

  private isMoving: boolean = false

  start() {
    // Listen for tap events on parent (world layer)
    if (this.node.parent) {
      this.node.parent.on(Node.EventType.TOUCH_END, this.onWorldTap, this)
    }
  }

  onWorldTap(event: EventTouch): void {
    if (this.isMoving) return

    const touchPos = event.getUILocation()
    this.moveTo(touchPos.x, touchPos.y)
  }

  moveTo(targetX: number, targetY: number): void {
    if (this.isMoving) return
    this.isMoving = true

    const currentPos = this.node.position
    const dx = targetX - currentPos.x
    const dy = targetY - currentPos.y
    const distance = Math.sqrt(dx * dx + dy * dy)
    const duration = distance / this.moveSpeed

    tween(this.node)
      .to(duration, { position: new Vec3(targetX, targetY, 0) })
      .call(() => {
        this.isMoving = false
      })
      .start()
  }
}
