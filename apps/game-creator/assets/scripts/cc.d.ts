// Type stub for CocosCreator 'cc' module
// Real types come from CocosCreator editor at build time
declare module 'cc' {
  export class Node {
    name: string
    active: boolean
    position: Vec3
    scale: Vec3
    children: Node[]
    setParent(parent: Node | null): void
    getChildByName(name: string): Node | null
    getComponent<T>(cls: new (...args: unknown[]) => T): T | null
    setPosition(x: number | Vec3, y?: number, z?: number): void
    setScale(x: number | Vec3, y?: number, z?: number): void
    addChild(child: Node): void
    addComponent<T>(cls: new (...args: unknown[]) => T): T
    destroy(): boolean
    destroyAllChildren(): void
    constructor(name?: string)
  }
  export class Vec3 {
    constructor(x?: number, y?: number, z?: number)
    x: number
    y: number
    z: number
  }
  export class Label extends Component {
    string: string
    fontSize: number
    color: Color
  }
  export class Sprite extends Component {
    color: Color
    spriteFrame: SpriteFrame | null
  }
  export class Color {
    constructor(r: number, g: number, b: number, a?: number)
    r: number
    g: number
    b: number
    a: number
  }
  export class SpriteFrame {}
  export class Component {
    node: Node
    enabled: boolean
    start(): void
    update(dt: number): void
    onDestroy(): void
  }
  export class Button extends Component {}
  export class ScrollView extends Component {}
  export class ProgressBar extends Component {
    progress: number
  }
  export class Asset {}
  export class Texture2D extends Asset {}
  export class SpriteAtlas extends Asset {}
  export class Prefab extends Asset {}
  export class AudioClip extends Asset {}
  export class Font extends Asset {}
  export class JsonAsset extends Asset {
    data: unknown
  }
  export interface TweenOptions {
    easing?: string
    onComplete?: () => void
  }
  export function tween<T extends object>(target: T): Tween<T>
  export interface Tween<T> {
    to(duration: number, props: Partial<T>, opts?: TweenOptions): Tween<T>
    by(duration: number, props: Partial<T>): Tween<T>
    delay(duration: number): Tween<T>
    call(cb: () => void): Tween<T>
    start(): void
    stop(): void
  }
  export function instantiate(prefab: Prefab): Node
  export function resourcesLoad<T extends Asset>(path: string, type: new () => T, cb: (err: Error | null, asset: T) => void): void
  export const macro: {
    DEBUG: boolean
  }
  export const _decorator: {
    ccclass: (name?: string) => ClassDecoratorFactory
    property: (options?: unknown) => PropertyDecorator
  }
  interface ClassDecoratorFactory {
    (target: Function): void
  }
  interface PropertyDecorator {
    (target: object, key: string | symbol): void
  }
}
