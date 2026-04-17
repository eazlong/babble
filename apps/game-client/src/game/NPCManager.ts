import { http } from '../network/HttpClient'

export interface NPCConfig {
  npc_id: string
  name: string
  dialogue_model: string
  voice_id: string
  avatar_ref: string
  cefr_level: string
  greeting: string
  topics: string[]
}

export class NPCManager {
  private npcs: Map<string, NPCConfig> = new Map()
  private activeNPC: NPCConfig | null = null

  async loadNPCs(sceneId: string): Promise<NPCConfig[]> {
    const { data, error } = await http.get<NPCConfig[]>(`/scenes/${sceneId}/npcs`)
    if (error ?? !data) {
      throw new Error(`Failed to load NPCs: ${error?.message}`)
    }

    this.npcs.clear()
    for (const npc of data) {
      this.npcs.set(npc.npc_id, npc)
    }
    return data
  }

  getNPC(npcId: string): NPCConfig | null {
    return this.npcs.get(npcId) ?? null
  }

  setActiveNPC(npcId: string): NPCConfig | null {
    const npc = this.npcs.get(npcId)
    if (npc) {
      this.activeNPC = npc
    }
    return npc ?? null
  }

  getActiveNPC(): NPCConfig | null {
    return this.activeNPC
  }
}
