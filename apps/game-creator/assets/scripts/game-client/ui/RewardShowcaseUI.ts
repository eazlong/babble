import { Label, Node, tween, Vec3, Sprite, Color } from 'cc'

export interface BadgeInfo {
  badge_id: string
  name: string
  description: string
  icon_ref: string
  earned_at?: string
  unlock_condition: string
  reward_preview: string
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
  private badgeListContainer: Node
  private earnedBadges: BadgeInfo[] = []
  private unearnedBadges: BadgeInfo[] = []

  constructor(rootNode: Node) {
    this.badgeContainer = rootNode.getChildByName('BadgeContainer')!
    this.lxpLabel = rootNode.getChildByName('LXPLabel')!.getComponent(Label)!
    this.levelLabel = rootNode.getChildByName('LevelLabel')!.getComponent(Label)!
    this.badgeListContainer = rootNode.getChildByName('BadgeListContainer')!
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

  setBadges(earned: BadgeInfo[], unearned: BadgeInfo[]): void {
    this.earnedBadges = earned
    this.unearnedBadges = unearned
    this.renderBadgeList()
  }

  showBadgeUnlockAnimation(badgeId: string): void {
    const badge = this.earnedBadges.find((b) => b.badge_id === badgeId)
    if (!badge) return

    // Create floating badge node for animation
    const animNode = new Node(`badge_${badgeId}`)
    animNode.setPosition(new Vec3(0, -200, 0))
    animNode.setScale(new Vec3(0.1, 0.1, 1))
    this.badgeContainer.addChild(animNode)

    // Add sprite component for badge icon
    const sprite = animNode.addComponent(Sprite)
    // sprite.spriteFrame would be set from asset cache using badge.icon_ref

    // Scale up + float up animation
    tween(animNode)
      .to(0.3, { scale: new Vec3(1.5, 1.5, 1) }, { easing: 'backOut' })
      .to(0.5, { position: new Vec3(0, 50, 0) })
      .delay(0.5)
      .to(0.3, { scale: new Vec3(1, 1, 1) })
      .call(() => {
        // Show badge info overlay
        this.showNewBadge(badge)
        animNode.destroy()
      })
      .start()
  }

  private renderBadgeList(): void {
    // Clear existing badge entries
    for (const child of this.badgeListContainer.children) {
      child.active = false
    }

    let index = 0

    // Render earned badges
    for (const badge of this.earnedBadges) {
      const node = this.badgeListContainer.children[index]
      if (node) {
        node.active = true
        const label = node.getComponent(Label)
        if (label) {
          label.string = `[${badge.name}] ${badge.description}`
        }
      }
      index++
    }

    // Render unearned badges (grayed out / locked)
    for (const badge of this.unearnedBadges) {
      const node = this.badgeListContainer.children[index]
      if (node) {
        node.active = true
        const label = node.getComponent(Label)
        if (label) {
          label.string = `[?] ${badge.unlock_condition}`
          label.color = new Color(128, 128, 128, 255)
        }
      }
      index++
    }

    this.badgeListContainer.active = index > 0
  }
}
