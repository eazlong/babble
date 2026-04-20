/**
 * ParallaxBackground - Multi-layer parallax scrolling for scene depth.
 */

import { _decorator, Component, Node, Vec3 } from 'cc'

const { ccclass, property } = _decorator

@ccclass('ParallaxBackground')
export class ParallaxBackground extends Component {
  @property(Node) farLayer: Node | null = null
  @property(Node) midLayer: Node | null = null
  @property(Node) nearLayer: Node | null = null

  @property({ tooltip: 'Parallax speed multipliers' })
  farSpeed: number = 0.1
  @property
  midSpeed: number = 0.3
  @property
  nearSpeed: number = 0.6

  private targetX: number = 0
  private targetY: number = 0

  update(_dt: number): void {
    this.applyParallax(this.farLayer, this.farSpeed)
    this.applyParallax(this.midLayer, this.midSpeed)
    this.applyParallax(this.nearLayer, this.nearSpeed)
  }

  setCameraTarget(x: number, y: number): void {
    this.targetX = x
    this.targetY = y
  }

  private applyParallax(layer: Node | null, speed: number): void {
    if (!layer) return
    layer.setPosition(
      -this.targetX * speed,
      -this.targetY * speed,
      layer.position.z,
    )
  }
}
