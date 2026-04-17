import { http } from '../network/HttpClient'

export interface SceneConfig {
  scene_id: string
  scene_name: string
  scene_type: string
  visual_assets_ref: string
  ambient_audio_ref: string
  npcs: Array<{ npc_id: string; position: { x: number; y: number } }>
  interactable_zones: Array<{
    zone_id: string
    trigger_type: 'proximity' | 'dialogue'
    action: string
  }>
}

export class SceneManager {
  private currentScene: SceneConfig | null = null
  private sceneAssets: Map<string, unknown> = new Map()

  async loadScene(sceneId: string): Promise<SceneConfig> {
    const { data, error } = await http.get<SceneConfig>(`/scenes/${sceneId}`)
    if (error ?? !data) {
      throw new Error(`Failed to load scene: ${error?.message}`)
    }

    this.currentScene = data
    await this.preloadAssets(data)
    return data
  }

  private async preloadAssets(scene: SceneConfig): Promise<void> {
    // Preload visual and audio assets from scene config
    const assetRefs = [scene.visual_assets_ref, scene.ambient_audio_ref]
    for (const ref of assetRefs) {
      if (ref && !this.sceneAssets.has(ref)) {
        // Asset loading would integrate with CocosCreator asset manager
        this.sceneAssets.set(ref, null)
      }
    }
  }

  getAvailableNPCs(): Array<{ npc_id: string; position: { x: number; y: number } }> {
    return this.currentScene?.npcs ?? []
  }

  getCurrentScene(): SceneConfig | null {
    return this.currentScene
  }

  unlockNextScene(_cefrLevel: string): string | null {
    // TODO: Implement CEFR-based scene unlocking logic
    return null
  }
}
