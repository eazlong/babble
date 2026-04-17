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

export class NPCEngine {
  private llmRouter: LLMRouter
  private contentFilter: SimpleContentFilter

  constructor() {
    this.llmRouter = new LLMRouter()
    this.contentFilter = new SimpleContentFilter()
  }

  async processDialogue(
    request: DialogueRequest,
    npc: NPCProfile,
    history: Array<{speaker: string, text: string}>
  ): Promise<DialogueResponse> {
    const systemPrompt = PromptManager.buildNPCSystemPrompt(npc, request.cefr_level)
    const context = PromptManager.buildDialogueContext(history)

    const userPrompt = context
      ? `${context}\n\nPlayer: ${request.player_input}\n\nRespond as ${npc.name}:`
      : `Player: ${request.player_input}\n\nRespond as ${npc.name}:`

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
        npc_text: 'I am not sure how to respond to that. Let us continue our conversation.',
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
