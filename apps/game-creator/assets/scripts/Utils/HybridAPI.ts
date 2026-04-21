/**
 * HybridAPI - Mixed backend + local fallback for all game data and interactions.
 * Tries local microservices first (localhost:830X), falls back to local mock data.
 */

import { SceneConfig } from '../game-client/game/SceneManager'

// Service endpoints
const SERVICES = {
  content: 'http://localhost:8308',
  dialogue: 'http://localhost:8309',
  quest: 'http://localhost:8310',
}

interface QuestData {
  quest_id: string
  title: string
  title_en: string
  description: string
  description_en: string
  quest_type: 'main' | 'sub' | 'daily'
  scene_id: string
  lxp_reward_base: number
  target_language_focus: string[]
  parent_quest_id?: string
}

interface DialogueResult {
  npc_text: string
  lxp_earned: number
  flagged: boolean
  badge_unlocked?: string
  stars_earned?: number
}

interface CompleteQuestResult {
  success: boolean
  lxp_earned: number
  stars_earned: number
  badge_unlocked: string | null
}

// Local fallback quest data (from quest-engine.ts)
const LOCAL_QUESTS: QuestData[] = [
  { quest_id: 'quest_forest_main', title: '探索精灵森林', title_en: 'Explore the Spirit Forest', description: '完成精灵森林中的所有任务', description_en: 'Complete all tasks in the Spirit Forest', quest_type: 'main', scene_id: 'spirit_forest', lxp_reward_base: 100, target_language_focus: ['greeting', 'colors', 'numbers'] },
  { quest_id: 'greet_oakley', title: '问候 Oakley', title_en: 'Greet Oakley', description: '用英语向森林精灵 Oakley 打招呼', description_en: 'Greet Oakley the forest spirit in English', quest_type: 'sub', scene_id: 'spirit_forest', lxp_reward_base: 30, target_language_focus: ['greeting', 'introductions'], parent_quest_id: 'quest_forest_main' },
  { quest_id: 'activate_flowers', title: '激活花朵', title_en: 'Activate the Flowers', description: '用颜色魔法激活森林中的花朵', description_en: 'Use color magic to activate the flowers', quest_type: 'sub', scene_id: 'spirit_forest', lxp_reward_base: 35, target_language_focus: ['colors', 'adjectives'], parent_quest_id: 'quest_forest_main' },
  { quest_id: 'open_chest', title: '打开宝箱', title_en: 'Open the Treasure Chest', description: '用数字魔法打开森林宝箱', description_en: 'Use number magic to open the chest', quest_type: 'sub', scene_id: 'spirit_forest', lxp_reward_base: 35, target_language_focus: ['numbers', 'counting'], parent_quest_id: 'quest_forest_main' },
  { quest_id: 'quest_library_main', title: '探索咒语图书馆', title_en: 'Explore the Spell Library', description: '完成咒语图书馆中的所有任务', description_en: 'Complete all tasks in the Spell Library', quest_type: 'main', scene_id: 'spell_library', lxp_reward_base: 100, target_language_focus: ['classroom', 'instructions', 'reading'] },
  { quest_id: 'organize_books', title: '整理魔法书', title_en: 'Organize the Magic Books', description: '按颜色和大小整理魔法书籍', description_en: 'Organize the magic books by color and size', quest_type: 'sub', scene_id: 'spell_library', lxp_reward_base: 30, target_language_focus: ['colors', 'sizes', 'adjectives'], parent_quest_id: 'quest_library_main' },
  { quest_id: 'follow_commands', title: '执行课堂指令', title_en: 'Follow Classroom Commands', description: '听从老师指令完成课堂任务', description_en: 'Follow teacher commands', quest_type: 'sub', scene_id: 'spell_library', lxp_reward_base: 35, target_language_focus: ['instructions', 'actions', 'classroom'], parent_quest_id: 'quest_library_main' },
  { quest_id: 'practice_dialogue', title: '与 Luna 对话练习', title_en: 'Practice Dialogue with Luna', description: '和 Luna 进行英语对话练习', description_en: 'Practice English conversation with Luna', quest_type: 'sub', scene_id: 'spell_library', lxp_reward_base: 35, target_language_focus: ['dialogue', 'questions', 'answers'], parent_quest_id: 'quest_library_main' },
  { quest_id: 'quest_garden_main', title: '探索彩虹花园', title_en: 'Explore the Rainbow Garden', description: '完成彩虹花园中的所有任务', description_en: 'Complete all tasks in the Rainbow Garden', quest_type: 'main', scene_id: 'rainbow_garden', lxp_reward_base: 100, target_language_focus: ['animals', 'weather', 'nature'] },
  { quest_id: 'fix_weather_crystal', title: '修复天气水晶', title_en: 'Fix the Weather Crystal', description: '修复花园中的天气水晶', description_en: 'Repair the weather crystal', quest_type: 'sub', scene_id: 'rainbow_garden', lxp_reward_base: 30, target_language_focus: ['weather', 'seasons'], parent_quest_id: 'quest_garden_main' },
  { quest_id: 'find_lost_animals', title: '找到迷路小动物', title_en: 'Find the Lost Animals', description: '在花园中找到迷路的小动物', description_en: 'Find the lost animals in the garden', quest_type: 'sub', scene_id: 'rainbow_garden', lxp_reward_base: 35, target_language_focus: ['animals', 'locations', 'directions'], parent_quest_id: 'quest_garden_main' },
  { quest_id: 'plant_flowers', title: '种植魔法花朵', title_en: 'Plant Magic Flowers', description: '在花园中种植魔法花朵', description_en: 'Plant magic flowers in the garden', quest_type: 'sub', scene_id: 'rainbow_garden', lxp_reward_base: 35, target_language_focus: ['nature', 'colors', 'verbs'], parent_quest_id: 'quest_garden_main' },
]

// NPC fallback responses for local mode
const NPC_RESPONSES: Record<string, string[]> = {
  'oakley': [
    'Hello, young one! Welcome to the Spirit Forest.',
    'Can you tell me the colors you see? Red, blue, or yellow?',
    'Good! Now, can you count from one to three?',
    'Wonderful! You are learning the magic of words!',
  ],
  'bookmark': [
    'Welcome to the Spell Library. Take your time, young one.',
    'Please open your book and read the first page.',
    'Now, listen carefully and repeat after me.',
  ],
  'luna': [
    'Hey! I\'m Luna! Let\'s practice magic spells together!',
    'Can you say "Stand up" and "Sit down"?',
    'Great job! Now try saying it again!',
  ],
  'petalia': [
    'Hello dear! I\'m Petalia. Can you help me with the garden?',
    'What\'s the weather like today? Is it sunny or rainy?',
    'Can you find the little cat? It\'s behind the tree!',
  ],
}

let responseIndex: Record<string, number> = {}

async function fetchJSON<T>(url: string, timeout: number = 2000): Promise<T | null> {
  try {
    const controller = new AbortController()
    const id = setTimeout(() => controller.abort(), timeout)
    const resp = await fetch(url, { signal: controller.signal })
    clearTimeout(id)
    if (!resp.ok) return null
    return (await resp.json()) as T
  } catch {
    return null
  }
}

async function postJSON<T>(url: string, body: unknown, timeout: number = 3000): Promise<T | null> {
  try {
    const controller = new AbortController()
    const id = setTimeout(() => controller.abort(), timeout)
    const resp = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
      signal: controller.signal,
    })
    clearTimeout(id)
    if (!resp.ok) return null
    return (await resp.json()) as T
  } catch {
    return null
  }
}

export class HybridAPI {
  private userId: string
  private online: boolean = false

  constructor(userId: string = 'anonymous') {
    this.userId = userId
  }

  /** Check if services are reachable */
  async pingServices(): Promise<boolean> {
    const health = await fetchJSON<{ status: string }>(`${SERVICES.content}/health`)
    this.online = health !== null
    return this.online
  }

  isOnline(): boolean {
    return this.online
  }

  /** Get scene config: service → local JSON fallback */
  async getSceneConfig(sceneId: string): Promise<SceneConfig | null> {
    const data = await fetchJSON<SceneConfig>(`${SERVICES.content}/api/v1/scenes/${sceneId}`)
    if (data) return data

    // Fallback: load from resources
    return this.loadLocalSceneConfig(sceneId)
  }

  /** Get quests for a scene: service → local quest data */
  async getSceneQuests(sceneId: string): Promise<QuestData[]> {
    const data = await fetchJSON<QuestData[]>(`${SERVICES.quest}/api/v1/quests?userId=${this.userId}&sceneId=${sceneId}`)
    if (data && data.length > 0) return data
    return LOCAL_QUESTS.filter((q) => q.scene_id === sceneId)
  }

  /** Complete a quest: service → local calculation */
  async completeQuest(
    questId: string,
    scores: { accuracy: number; fluency: number; vocabulary: number }
  ): Promise<CompleteQuestResult> {
    const data = await postJSON<CompleteQuestResult>(`${SERVICES.quest}/api/v1/quests/complete`, {
      quest_id: questId,
      ...scores,
    })
    if (data && data.success) return data

    // Local fallback: simple calculation
    const avg = (scores.accuracy + scores.fluency + scores.vocabulary) / 3
    const lxp = Math.round(avg)
    const stars = avg >= 90 ? 3 : avg >= 70 ? 2 : avg >= 40 ? 1 : 0
    return { success: true, lxp_earned: lxp, stars_earned: stars, badge_unlocked: null }
  }

  /** Get NPC greeting: uses NPC response pool */
  getNPCGreeting(npcId: string): string {
    const responses = NPC_RESPONSES[npcId]
    if (!responses) return 'Hello! Let\'s learn together!'
    const idx = responseIndex[npcId] || 0
    responseIndex[npcId] = (idx + 1) % responses.length
    return responses[idx]
  }

  /** Process dialogue: service → local NPC responses */
  async processDialogue(
    npcId: string,
    playerInput: string,
    sessionId: string = ''
  ): Promise<DialogueResult> {
    const data = await postJSON<DialogueResult>(`${SERVICES.dialogue}/api/v1/dialogue`, {
      user_id: this.userId,
      npc_id: npcId,
      player_input: playerInput,
      session_id: sessionId,
      language: 'en',
      cefr_level: 'A1',
    })
    if (data) return data

    // Local fallback: simple keyword matching
    return this.localDialogueResponse(npcId, playerInput)
  }

  private async loadLocalSceneConfig(sceneId: string): Promise<SceneConfig | null> {
    try {
      // Try loading from CocosCreator resources
      const configs: Record<string, any> = {
        spirit_forest: await this.loadJsonResource('configs/scenes/spirit_forest'),
        spell_library: await this.loadJsonResource('configs/scenes/spell_library'),
        rainbow_garden: await this.loadJsonResource('configs/scenes/rainbow_garden'),
      }
      const local = configs[sceneId]
      if (!local) return null

      return {
        scene_id: local.scene_id,
        scene_name: local.scene_name,
        scene_type: 'chapter',
        visual_assets_ref: `${sceneId}_bg`,
        ambient_audio_ref: `${sceneId}_ambience`,
        description: local.description,
        npcs: local.npcs || [],
        vocabulary_focus: local.vocabulary_focus || [],
        tasks: (local.tasks || []).map((t: string) => ({
          task_id: t, title: t, title_en: t, description: '', required_lxp: 30,
        })),
        badge_id: local.badge_id || '',
        required_lxp: local.required_lxp || 0,
        interactable_zones: (local.interactable_zones || []).map((z: any) => ({
          zone_id: z.zone_id,
          trigger_type: z.trigger_type,
          action: z.action,
        })),
      } as SceneConfig
    } catch {
      return null
    }
  }

  private loadJsonResource(path: string): Promise<any> {
    return new Promise((resolve, reject) => {
      // CocosCreator resources.load API
      if (typeof cc !== 'undefined' && cc.resourcesLoad) {
        cc.resourcesLoad(path, cc.JsonAsset, (err: Error | null, asset: any) => {
          if (err) reject(err)
          else resolve(asset.json)
        })
      } else {
        reject(new Error('cc not available'))
      }
    })
  }

  private localDialogueResponse(npcId: string, input: string): DialogueResult {
    const responses = NPC_RESPONSES[npcId] || ['Good try! Let\'s keep practicing.']
    const idx = responseIndex[npcId] || 0
    responseIndex[npcId] = (idx + 1) % responses.length

    const words = input.trim().split(/\s+/).length
    const lxp = Math.min(100, Math.max(10, words * 5))
    const stars = input.length > 3 ? 2 : 1

    return {
      npc_text: responses[idx],
      lxp_earned: lxp,
      flagged: false,
      stars_earned: stars,
    }
  }
}
