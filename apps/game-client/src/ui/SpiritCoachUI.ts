import { Color, Label, Node, Sprite, Vec3, tween } from 'cc'

export type CoachMood = 'correct' | 'suggestion' | 'needs_correction' | 'neutral'

export class SpiritCoachUI {
  private spriteNode: Node
  private hintLabel: Label
  private glowSprite: Sprite
  private isVisible = true

  constructor(rootNode: Node) {
    this.spriteNode = rootNode.getChildByName('SpiritSprite')!
    this.hintLabel = rootNode.getChildByName('HintLabel')!.getComponent(Label)!
    this.glowSprite = rootNode.getChildByName('Glow')!.getComponent(Sprite)!
  }

  showHint(text: string, mood: CoachMood): void {
    this.hintLabel.string = text
    this.setGlowColor(mood)
    this.animateHint()
  }

  private setGlowColor(mood: CoachMood): void {
    const colors: Record<CoachMood, [number, number, number]> = {
      correct: [0.2, 0.8, 0.2],
      suggestion: [1.0, 0.6, 0.2],
      needs_correction: [1.0, 0.2, 0.2],
      neutral: [1.0, 1.0, 0.8]
    }
    const [r, g, b] = colors[mood]
    this.glowSprite.color = new Color(r * 255, g * 255, b * 255, 200)
  }

  private animateHint(): void {
    this.spriteNode.setPosition(0, -50, 0)
    tween(this.spriteNode).to(0.3, { position: new Vec3(0, 0, 0) }).start()
  }

  setVisible(visible: boolean): void {
    this.isVisible = visible
    this.spriteNode.active = visible
  }

  announceQuest(questTitle: string, questDescription: string): void {
    this.showHint(`New Quest: ${questTitle}\n${questDescription}`, 'neutral')
  }

  playCelebration(): void {
    if (!this.spriteNode || !this.isVisible) return
    tween(this.spriteNode)
      .by(0.15, { position: new Vec3(0, 10, 0) })
      .by(0.15, { position: new Vec3(0, -10, 0) })
      .by(0.15, { position: new Vec3(0, 10, 0) })
      .by(0.15, { position: new Vec3(0, -10, 0) })
      .start()
  }
}
