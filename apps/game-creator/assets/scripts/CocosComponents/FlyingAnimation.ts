/**
 * FlyingAnimation - 动态加载并播放精灵飞行动画
 * 从 flying 文件夹加载 56-64 帧图片，创建循环播放的动画
 */

import { _decorator, Component, Sprite, SpriteFrame, AnimationClip, Animation, resources, Texture2D, UITransform } from 'cc'
const { ccclass, property } = _decorator

const FRAME_COUNT = 8
const FRAME_PREFIX = 'textures/characters/sprite_coach/flying/'
const FRAME_DURATION = 0.15 // 每帧持续时间(秒)

@ccclass('FlyingAnimation')
export class FlyingAnimation extends Component {
  private animation: Animation | null = null
  private sprite: Sprite | null = null
  private framesLoaded: boolean = false

  start() {
    this.sprite = this.node.getComponent(Sprite)
    this.animation = this.node.getComponent(Animation)

    if (!this.sprite) {
      this.sprite = this.node.addComponent(Sprite)
    }

    if (!this.animation) {
      this.animation = this.node.addComponent(Animation)
    }

    // 设置 UITransform 尺寸
    const uiTransform = this.node.getComponent(UITransform)
    if (uiTransform) {
      uiTransform.setContentSize(480, 270)
    }

    this.loadFramesAndCreateAnimation()
  }

  private async loadFramesAndCreateAnimation(): Promise<void> {
    const spriteFrames: SpriteFrame[] = []

    // 加载所有帧 (57-64)
    // CocosCreator 3.x: 加载 Texture2D 子资源，然后创建 SpriteFrame
    for (let i = 57; i <= 64; i++) {
      const texturePath = `${FRAME_PREFIX}${i}_480x270/texture`
      try {
        const frame = await this.loadSpriteFrame(texturePath)
        if (frame) {
          spriteFrames.push(frame)
          console.log(`[FlyingAnimation] Loaded frame ${i}`)
        }
      } catch (error) {
        console.warn(`[FlyingAnimation] Failed to load frame ${i}:`, error)
      }
    }

    if (spriteFrames.length === 0) {
      console.error('[FlyingAnimation] No frames loaded!')
      return
    }

    this.framesLoaded = true
    console.log('[FlyingAnimation] Total frames loaded:', spriteFrames.length)
    this.createAndPlayAnimation(spriteFrames)
  }

  private loadSpriteFrame(path: string): Promise<SpriteFrame | null> {
    return new Promise((resolve) => {
      // CocosCreator 3.x: 加载 Texture2D 子资源，创建 SpriteFrame
      resources.load(path, Texture2D, (err, texture) => {
        if (err) {
          console.error('[FlyingAnimation] Load error for', path, err)
          resolve(null)
          return
        }
        const spriteFrame = new SpriteFrame()
        spriteFrame.texture = texture
        resolve(spriteFrame)
      })
    })
  }

  private createAndPlayAnimation(frames: SpriteFrame[]): void {
    // 创建动画剪辑
    const clip = AnimationClip.createWithSpriteFrames(frames, FRAME_DURATION)

    if (!clip) {
      console.error('[FlyingAnimation] Failed to create animation clip!')
      return
    }

    clip.name = 'Flying'
    clip.wrapMode = AnimationClip.WrapMode.Loop
    clip.speed = 30

    // 设置初始帧
    if (this.sprite && frames.length > 0) {
      this.sprite.spriteFrame = frames[0]
    }

    // 添加动画剪辑并播放
    this.animation!.addClip(clip)
    this.animation!.defaultClip = clip
    this.animation!.play('Flying')

    console.log('[FlyingAnimation] Animation started with', frames.length, 'frames')
  }

  /**
   * 暂停动画
   */
  pauseAnimation(): void {
    if (this.animation && this.framesLoaded) {
      this.animation.pause()
    }
  }

  /**
   * 继续动画
   */
  resumeAnimation(): void {
    if (this.animation && this.framesLoaded) {
      this.animation.resume()
    }
  }

  /**
   * 设置动画速度
   */
  setSpeed(speed: number): void {
    if (this.animation && this.animation.defaultClip) {
      this.animation.defaultClip.speed = speed
    }
  }
}