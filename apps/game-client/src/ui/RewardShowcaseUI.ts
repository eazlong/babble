import { Label, Node, tween, Vec3 } from 'cc'

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

  showNewBadge(_badge: BadgeInfo): void {
    // Animate badge appearance
    const badgeNode = new Node('badge')
    this.badgeContainer.addChild(badgeNode)
    badgeNode.setPosition(new Vec3(0, 0, 0))

    tween(badgeNode)
      .to(0.5, { scale: new Vec3(1, 1, 1) })
      .start()
  }

  hide(): void {
    this.badgeContainer.active = false
  }

  show(): void {
    this.badgeContainer.active = true
  }
}
