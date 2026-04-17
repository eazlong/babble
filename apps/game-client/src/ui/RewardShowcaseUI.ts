import { Label, Node, tween } from 'cc'

export interface BadgeInfo {
  badge_id: string
  name: string
  description: string
  icon_ref: string
  earned_at: string
}

export interface LXPInfo {
  current: number
  to_next_level: number
  level: number
}

export class RewardShowcaseUI {
  private badgeContainer: Node
  private lxpLabel: Label
  private levelLabel: Label

  constructor(rootNode: Node) {
    this.badgeContainer = rootNode.getChildByName('BadgeContainer')!
    this.lxpLabel = rootNode.getChildByName('LXPLabel')!.getComponent(Label)!
    this.levelLabel = rootNode.getChildByName('LevelLabel')!.getComponent(Label)!
  }

  updateLXP(info: LXPInfo): void {
    this.lxpLabel.string = `${info.current}/${info.to_next_level} LXP`
    this.levelLabel.string = `Level ${info.level}`
  }

  showNewBadge(badge: BadgeInfo): void {
    // Create a new badge node and animate it
    const badgeNode = new Node(`badge_${badge.badge_id}`)
    this.badgeContainer.addChild(badgeNode)

    tween(badgeNode)
      .from(0, { scale: new (class { x: number; y: number; z: number } = class { x = 0; y = 0; z = 0 }) })
      .to(0.5, { scale: new (class { x: number; y: number; z: number } = class { x = 1; y = 1; z = 1 }) })
      .start()
  }

  hide(): void {
    this.badgeContainer.active = false
  }

  show(): void {
    this.badgeContainer.active = true
  }
}
