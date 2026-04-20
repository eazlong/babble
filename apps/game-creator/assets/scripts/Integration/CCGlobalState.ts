/**
 * CCGlobalState - Cross-scene persistent singleton holding the GameWorld instance.
 * Uses game.addPersistRootNode() to survive scene transitions.
 */

import { _decorator, Component, Node, game } from 'cc'
import { GameWorld } from '@linguaquest/game-client/game/GameWorld'

const { ccclass, property } = _decorator

class GlobalState {
  private static _instance: GlobalState
  private _gameWorld: GameWorld | null = null

  static get instance(): GlobalState {
    if (!this._instance) {
      this._instance = new GlobalState()
    }
    return this._instance
  }

  get gameWorld(): GameWorld {
    if (!this._gameWorld) {
      this._gameWorld = new GameWorld()
    }
    return this._gameWorld
  }

  reset(): void {
    this._gameWorld = null
  }
}

@ccclass('CCGlobalState')
export class CCGlobalState extends Component {
  @property(Node) hudNode: Node | null = null

  static getInstance(): GlobalState {
    return GlobalState.instance
  }

  onLoad() {
    // Persist this node across scene transitions
    game.addPersistRootNode(this.node)
  }

  start() {
    // Initialize the game world
    const world = GlobalState.instance.gameWorld
    console.log('[CCGlobalState] GameWorld initialized')

    // Persist HUD node if provided
    if (this.hudNode) {
      game.addPersistRootNode(this.hudNode)
    }
  }
}
