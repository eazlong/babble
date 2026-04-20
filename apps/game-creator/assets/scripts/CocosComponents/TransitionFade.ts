/**
 * TransitionFade - Scene transition fade-in/fade-out effect.
 */

import { _decorator, Component, Node, tween, Color, Sprite } from 'cc'

const { ccclass, property } = _decorator

@ccclass('TransitionFade')
export class TransitionFade extends Component {
  @property(Sprite) fadeSprite: Sprite | null = null
  @property({ tooltip: 'Fade duration in seconds' })
  fadeDuration: number = 0.5

  private static _instance: TransitionFade | null = null

  static async fadeOut(callback: () => void, duration: number = 0.5): Promise<void> {
    if (!this._instance) return
    this._instance.performFade(callback, true, duration)
  }

  start() {
    TransitionFade._instance = this

    // Start with full black overlay
    if (this.fadeSprite) {
      this.fadeSprite.color = new Color(0, 0, 0, 255)
    }

    // Fade in to transparent
    this.fadeIn(() => {})
  }

  private fadeIn(callback: () => void): void {
    if (!this.fadeSprite) {
      callback()
      return
    }

    const startColor = { ...this.fadeSprite.color }
    tween(this.fadeSprite)
      .to(this.fadeDuration, { color: new Color(startColor.r, startColor.g, startColor.b, 0) })
      .call(callback)
      .start()
  }

  private performFade(callback: () => void, fadeOut: boolean, duration: number): void {
    if (!this.fadeSprite) {
      callback()
      return
    }

    const targetAlpha = fadeOut ? 255 : 0
    tween(this.fadeSprite)
      .to(duration, { color: new Color(0, 0, 0, targetAlpha) })
      .call(() => {
        if (!fadeOut) callback()
      })
      .start()
  }
}
