import OpenAI from 'openai'
import { PromptBuilder, type Trigger, type StreakData } from './prompt-builder.js'
import { coachResponseSchema, type CoachInput, type CoachResponse } from '../types/coach-events.js'

export interface LLMCoachOptions {
  openai?: OpenAI
  model?: string
  timeoutMs?: number
}

export interface LLMCoachResult {
  response: CoachResponse
  tokenUsage?: {
    promptTokens: number
    completionTokens: number
    totalTokens: number
  }
}

export class LLMCoach {
  private openai: OpenAI
  private model: string
  private timeoutMs: number
  private promptBuilder: PromptBuilder

  constructor(options: LLMCoachOptions = {}) {
    const apiKey = options.openai
      ? undefined // DI mode: skip key check (mock in tests)
      : process.env.OPENAI_API_KEY
    if (!options.openai && !apiKey) {
      throw new Error('LLMCoach: OPENAI_API_KEY environment variable is required')
    }
    this.openai = options.openai ?? new OpenAI({ apiKey: apiKey! })
    this.model = options.model ?? process.env.COACH_LLM_MODEL ?? 'gpt-4o-mini'
    this.timeoutMs = options.timeoutMs ?? 5000
    this.promptBuilder = new PromptBuilder()
  }

  async generate(input: CoachInput, trigger: Trigger, streak?: StreakData): Promise<CoachResponse> {
    return (await this.generateWithUsage(input, trigger, streak)).response
  }

  async generateWithUsage(input: CoachInput, trigger: Trigger, streak?: StreakData): Promise<LLMCoachResult> {
    const { system, user } = await this.promptBuilder.build(trigger, input, streak)

    let timeoutId: NodeJS.Timeout | undefined
    try {
      const callPromise = this.openai.chat.completions.create({
        model: this.model,
        messages: [
          { role: 'system', content: system },
          { role: 'user', content: user },
        ],
        response_format: { type: 'json_object' },
        temperature: 0.7,
        max_tokens: 300,
      })

      const timeoutPromise = new Promise<never>((_, reject) => {
        timeoutId = setTimeout(
          () => reject(new Error(`LLM timeout after ${this.timeoutMs}ms`)),
          this.timeoutMs,
        )
      })

      const response = await Promise.race([callPromise, timeoutPromise])

      const content = response.choices[0]?.message?.content
      if (!content) {
        throw new Error('Empty LLM response')
      }

      let parsed: unknown
      try {
        parsed = JSON.parse(content)
      } catch {
        throw new Error(`Invalid JSON from LLM: ${content.slice(0, 200)}`)
      }

      const coachResponse = coachResponseSchema.parse(parsed)
      return {
        response: coachResponse,
        tokenUsage: response.usage ? {
          promptTokens: response.usage.prompt_tokens,
          completionTokens: response.usage.completion_tokens,
          totalTokens: response.usage.total_tokens,
        } : undefined,
      }
    } finally {
      if (timeoutId !== undefined) clearTimeout(timeoutId)
    }
  }
}
