import { LLMRouter, LLMResponse } from './llm-router.js'
import { PromptManager, NPCProfile } from './prompt-manager.js'

export interface DialogueRequest {
  user_id: string
  npc_id: string
  player_input: string
  session_id: string
  language: string
  cefr_level: string
  quest_context?: string
}

export interface DialogueResponse {
  npc_text: string
  audio_url: string
  lxp_earned: number
  flagged: boolean
}

class SimpleContentFilter {
  private blockedPatterns: RegExp[] = [
    /(?:kill|die|death|hurt)/i,
    /(?:blood|weapon|fight)/i,
  ]

  async check(text: string, isChildMode: boolean = false): Promise<{ safe: boolean }> {
    if (!isChildMode) return { safe: true }
    for (const pattern of this.blockedPatterns) {
      if (pattern.test(text)) return { safe: false }
    }
    return { safe: true }
  }
}

const ENCOURAGING_RESPONSES: string[] = [
  "Good try! Let me help you.",
  "That's close! Try saying it this way.",
  "You're doing great! Let's try again.",
  "Nice effort! Here's how we say it.",
]

export class NPCEngine {
  private llmRouter: LLMRouter
  private contentFilter: SimpleContentFilter

  constructor() {
    this.llmRouter = new LLMRouter()
    this.contentFilter = new SimpleContentFilter()
  }

  buildTeachingContext(npc: NPCProfile): string | null {
    if (!npc.teaches || npc.teaches.length === 0) return null
    const topics = npc.teaches.join(', ')
    return `I am teaching: ${topics}. Use simple A1-level English. Encourage the student.`
  }

  async processDialogue(
    request: DialogueRequest,
    npc: NPCProfile,
    history: Array<{speaker: string, text: string}>
  ): Promise<DialogueResponse> {
    const systemPrompt = PromptManager.buildNPCSystemPrompt(npc, request.cefr_level)
    const context = PromptManager.buildDialogueContext(history)

    const teachingContext = this.buildTeachingContext(npc)

    let userPrompt = context
      ? `${context}\n\nPlayer: ${request.player_input}\n\nRespond as ${npc.name}:`
      : `Player: ${request.player_input}\n\nRespond as ${npc.name}:`

    if (teachingContext) {
      userPrompt = `${userPrompt}\n\n[${teachingContext}]`
    }

    const fullPrompt = request.quest_context
      ? `${userPrompt}\n\n[Current quest: ${request.quest_context}]`
      : userPrompt

    const llmResponse = await this.llmRouter.generate(
      `${systemPrompt}\n\n${fullPrompt}`,
      'npc_dialogue',
      300
    )

    const moderation = await this.contentFilter.check(llmResponse.text)

    if (!moderation.safe) {
      return {
        npc_text: ENCOURAGING_RESPONSES[
          Math.floor(Math.random() * ENCOURAGING_RESPONSES.length)
        ],
        audio_url: '',
        lxp_earned: 0,
        flagged: true
      }
    }

    return {
      npc_text: llmResponse.text,
      audio_url: '',
      lxp_earned: this.calculateLXP(request.player_input, llmResponse.text),
      flagged: false
    }
  }

  private calculateLXP(playerInput: string, _npcResponse: string): number {
    const words = playerInput.split(/\s+/).length
    return Math.min(100, Math.max(10, words * 5))
  }
}
