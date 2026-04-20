/**
 * InteractiveZone - Proximity/dialogue trigger zone attached to interactive elements
 * in the scene (flowers, chests, books, etc.).
 */

import { _decorator, Component, Node, BoxCollider2D } from 'cc'

const { ccclass, property } = _decorator

@ccclass('InteractiveZone')
export class InteractiveZone extends Component {
  @property({ tooltip: 'Zone identifier' })
  zoneId: string = ''

  @property({ tooltip: 'Trigger type' })
  triggerType: 'proximity' | 'dialogue' = 'proximity'

  @property({ tooltip: 'Action to perform on trigger' })
  action: string = ''

  @property({ tooltip: 'Is this zone currently active' })
  isActive: boolean = true

  onTriggerEnter(): void {
    if (!this.isActive) return
    this.node.emit('zone_triggered', {
      zoneId: this.zoneId,
      triggerType: this.triggerType,
      action: this.action,
    })
  }

  activate(): void {
    this.isActive = true
  }

  deactivate(): void {
    this.isActive = false
  }
}
