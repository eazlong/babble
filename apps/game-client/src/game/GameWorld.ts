import { SceneManager } from './SceneManager'
import { NPCManager } from './NPCManager'

export interface QuestInfo {
  quest_id: string
  title: string
  title_en: string
  description: string
  target_npc_id: string
  required_dialogue_turns: number
  reward_lxp: number
  sub_quests?: Array<{
    sub_quest_id: string
    title: string
    title_en: string
    completed: boolean
  }>
}

export interface StoryProgress {
  current_scene_id: string
  completed_quests: string[]
  earned_badges: string[]
  total_lxp: number
}

export class GameWorld {
  private sceneManager: SceneManager
  private npcManager: NPCManager
  private currentQuests: QuestInfo[] = []
  private storyProgress: StoryProgress = {
    current_scene_id: '',
    completed_quests: [],
    earned_badges: [],
    total_lxp: 0,
  }

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
    if (!this.canEnterScene(sceneId)) {
      throw new Error(
        `Scene "${sceneId}" is locked. Required LXP: ${this.getSceneRequiredLxp(sceneId)}, ` +
        `Current LXP: ${this.storyProgress.total_lxp}`,
      )
    }

    const scene = await this.sceneManager.loadScene(sceneId)
    await this.npcManager.loadNPCs(sceneId)

    this.storyProgress.current_scene_id = sceneId

    // Load quests for this scene
    this.currentQuests = this.getDefaultQuestsForScene(sceneId)

    // Wire up badge tracking from scene config
    if (scene.badge_id && !this.storyProgress.earned_badges.includes(scene.badge_id)) {
      // Badge will be earned upon scene completion
    }
  }

  canEnterScene(sceneId: string): boolean {
    const requiredLxp = this.getSceneRequiredLxp(sceneId)
    return this.storyProgress.total_lxp >= requiredLxp
  }

  advanceStory(completedQuestId: string, earnedLxp: number): void {
    if (!this.storyProgress.completed_quests.includes(completedQuestId)) {
      this.storyProgress.completed_quests.push(completedQuestId)
    }
    this.storyProgress.total_lxp += earnedLxp

    // Check if current scene's badge should be awarded
    const scene = this.sceneManager.getCurrentScene()
    if (scene?.badge_id) {
      const sceneProgress = this.sceneManager.getSceneProgress()
      if (sceneProgress?.badge_earned && !this.storyProgress.earned_badges.includes(scene.badge_id)) {
        this.storyProgress.earned_badges.push(scene.badge_id)
      }
    }
  }

  getStoryProgress(): StoryProgress {
    return {
      ...this.storyProgress,
      completed_quests: [...this.storyProgress.completed_quests],
      earned_badges: [...this.storyProgress.earned_badges],
    }
  }

  getEarnedBadges(): string[] {
    return [...this.storyProgress.earned_badges]
  }

  hasBadge(badgeId: string): boolean {
    return this.storyProgress.earned_badges.includes(badgeId)
  }

  addBadge(badgeId: string): void {
    if (!this.storyProgress.earned_badges.includes(badgeId)) {
      this.storyProgress.earned_badges.push(badgeId)
    }
  }

  private getSceneRequiredLxp(_sceneId: string): number {
    const scene = this.sceneManager.getCurrentScene()
    return scene?.required_lxp ?? 0
  }

  private getDefaultQuestsForScene(_sceneId: string): QuestInfo[] {
    // TODO: Fetch quests from server
    return []
  }

  getCurrentQuests(): QuestInfo[] {
    return [...this.currentQuests]
  }
}
