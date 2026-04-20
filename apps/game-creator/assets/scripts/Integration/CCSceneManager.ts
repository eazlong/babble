/**
 * CCSceneManager - Wraps the game-client SceneManager, integrates with
 * CocosCreator's assetManager for resource loading and director for scene transitions.
 */

import { _decorator, Component, director, assetManager, SceneAsset } from 'cc'
import { SceneManager, SceneConfig } from '@linguaquest/game-client/game/SceneManager'
import { CCGlobalState } from './CCGlobalState'

const { ccclass, property } = _decorator

@ccclass('CCSceneManager')
export class CCSceneManager extends Component {
  private manager: SceneManager
  private currentSceneId: string = ''

  constructor() {
    super()
    this.manager = new SceneManager()
  }

  async loadScene(sceneId: string): Promise<SceneConfig | null> {
    try {
      const config = await this.manager.loadScene(sceneId)
      this.currentSceneId = sceneId

      // Load CocosCreator scene by ID
      const ccSceneName = this.toCCSceneName(sceneId)
      director.loadScene(ccSceneName)

      return config
    } catch (error) {
      console.error(`[CCSceneManager] Failed to load scene ${sceneId}:`, error)
      return null
    }
  }

  preloadSceneAssets(sceneId: string): Promise<void> {
    return new Promise((resolve) => {
      const ccSceneName = this.toCCSceneName(sceneId)
      assetManager.loadBundle(ccSceneName, (err, bundle) => {
        if (err) {
          console.warn(`[CCSceneManager] Bundle not found for ${ccSceneName}`)
        }
        resolve()
      })
    })
  }

  getCurrentScene(): SceneConfig | null {
    return this.manager.getCurrentScene()
  }

  getAvailableNPCs(): Array<{ npc_id: string; position: { x: number; y: number } }> {
    return this.manager.getAvailableNPCs()
  }

  isSceneUnlocked(userLxp: number): boolean {
    return this.manager.isSceneUnlocked(userLxp)
  }

  private toCCSceneName(sceneId: string): string {
    // spirit_forest -> SpiritForest, spell_library -> SpellLibrary
    return sceneId
      .split('_')
      .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
      .join('')
  }
}
