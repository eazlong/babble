import { SceneManager } from './SceneManager'
import { NPCManager } from './NPCManager'

export interface QuestInfo {
  quest_id: string
  title: string
  description: string
  target_npc_id: string
  required_dialogue_turns: number
  reward_lxp: number
}

export class GameWorld {
  private sceneManager: SceneManager
  private npcManager: NPCManager
  private currentQuests: QuestInfo[] = []

  constructor() {
    this.sceneManager = new SceneManager()
    this.npcManager = new NPCManager()
  }

  getSceneManager(): SceneManager {
    return this.sceneManager
  }

  getNPCManager(): NPCManager {
    return this.npcManager
  }

  async enterScene(sceneId: string): Promise<void> {
    const scene = await this.sceneManager.loadScene(sceneId)
    await this.npcManager.loadNPCs(sceneId)

    // Load quests for this scene
    this.currentQuests = this.getDefaultQuestsForScene(sceneId)
  }

  private getDefaultQuestsForScene(_sceneId: string): QuestInfo[] {
    // TODO: Fetch quests from server
    return []
  }

  getCurrentQuests(): QuestInfo[] {
    return [...this.currentQuests]
  }
}
