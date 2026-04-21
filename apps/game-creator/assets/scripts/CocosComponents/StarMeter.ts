/**
 * StarMeter - HUD element displaying current LXP, level, and star progress.
 * Listens for quest_completed events and animates progress changes.
 */

import { _decorator, Component, Label, ProgressBar, Node, tween } from 'cc'
import { CCGlobalState } from '../Integration/CCGlobalState'

const { ccclass, property } = _decorator

@ccclass('StarMeter')
export class StarMeter extends Component {
  @property(Label) xpLabel: Label | null = null
  @property(Label) levelLabel: Label | null = null
  @property(ProgressBar) progressBar: ProgressBar | null = null
  @property(Node) starContainer: Node | null = null

  private currentLXP: number = 0
  private targetLXP: number = 0
  private levelThresholds: number[] = [30, 60, 90, 120, 150, 200, 250, 300]

  start() {
    // Listen for quest completion
    this.node.on('quest_completed', (data) => {
      this.addLXP(data.earnedLxp)
    })

    // Listen for scene change to update display
    this.node.on('scene_entered', () => {
      this.updateDisplay()
    })

    this.updateDisplay()
  }

  addLXP(amount: number): void {
    this.targetLXP = this.currentLXP + amount
    this.animateProgress(this.currentLXP, this.targetLXP)
    this.currentLXP = this.targetLXP
  }

  private animateProgress(from: number, to: number): void {
    // Animate progress bar over 1 second
    const fromProgress = this.getProgressForLXP(from)
    const toProgress = this.getProgressForLXP(to)

    if (this.progressBar) {
      this.progressBar.progress = fromProgress
      tween({ value: fromProgress })
        .to(1.0, { value: toProgress }, {
          onUpdate: (obj) => {
            if (this.progressBar) this.progressBar.progress = obj.value
          },
        })
        .start()
    }

    // Show floating "+N LXP" briefly
    this.showFloatingGain(to - from)
  }

  private showFloatingGain(gain: number): void {
    // Simple: update label to show gain
    if (this.xpLabel) {
      const originalText = this.xpLabel.string
      this.xpLabel.string = `+${gain} LXP!`
      setTimeout(() => {
        if (this.xpLabel) this.xpLabel.string = originalText
      }, 1500)
    }
  }

  updateDisplay(): void {
    const state = CCGlobalState.getInstance()
    const progress = state.gameWorld.getStoryProgress()
    this.currentLXP = progress.total_lxp
    this.targetLXP = progress.total_lxp

    if (this.progressBar) {
      this.progressBar.progress = this.getProgressForLXP(this.currentLXP)
    }

    if (this.levelLabel) {
      const level = this.getLevelForLXP(this.currentLXP)
      this.levelLabel.string = `Lv.${level}`
    }

    if (this.xpLabel) {
      const nextThreshold = this.getNextThreshold(this.currentLXP)
      this.xpLabel.string = `${this.currentLXP}/${nextThreshold}`
    }
  }

  private getProgressForLXP(lxp: number): number {
    const currentThreshold = this.getLevelThreshold(this.getLevelForLXP(lxp))
    const nextThreshold = this.getNextThreshold(lxp)
    if (nextThreshold <= currentThreshold) return 1.0
    return (lxp - currentThreshold) / (nextThreshold - currentThreshold)
  }

  private getLevelForLXP(lxp: number): number {
    let level = 1
    for (const threshold of this.levelThresholds) {
      if (lxp >= threshold) level++
      else break
    }
    return level
  }

  private getLevelThreshold(level: number): number {
    if (level <= 1) return 0
    return this.levelThresholds[level - 2] || this.levelThresholds[this.levelThresholds.length - 1]
  }

  private getNextThreshold(lxp: number): number {
    for (const threshold of this.levelThresholds) {
      if (lxp < threshold) return threshold
    }
    return this.levelThresholds[this.levelThresholds.length - 1]
  }
}
