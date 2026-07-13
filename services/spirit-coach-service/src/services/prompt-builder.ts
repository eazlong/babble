import { readFile } from 'node:fs/promises'
import { join, dirname } from 'node:path'
import { fileURLToPath } from 'node:url'
import type { CoachInput } from '../types/coach-events.js'

const __dirname = dirname(fileURLToPath(import.meta.url))
const PROMPTS_DIR = join(__dirname, '../../prompts')

export type Trigger = 'wake' | 'error' | 'silence'

export interface PromptContext {
  player_level: string
  player_text: string
  npc_response: string
  silence_seconds: number
  recent_turns: string // pre-formatted
}

export interface PromptBundle {
  system: string
  user: string
}

/**
 * Simple template renderer supporting:
 * - {{variable}} → string replacement
 * - {{#if var}}...{{/if}} → conditional block (content shown if var is truthy/non-empty)
 */
export function renderTemplate(template: string, vars: Record<string, string | undefined>): string {
  // Handle {{#if var}}...{{/if}} blocks
  let result = template.replace(
    /\{\{#if (\w+)\}\}([\s\S]*?)\{\{\/if\}\}/g,
    (_, name, content) => {
      const value = vars[name]
      if (value && value.length > 0) {
        return content
      }
      return ''
    }
  )

  // Handle {{variable}} replacements
  result = result.replace(/\{\{(\w+)\}\}/g, (_, name) => {
    return vars[name] ?? ''
  })

  return result
}

export function buildContextFromInput(input: CoachInput): PromptContext {
  const player_level = input.player_level ?? 'A1'

  let player_text = ''
  let npc_response = ''
  let silence_seconds = 0

  if (input.event_type === 'dialogue_turn') {
    player_text = input.player_text
    npc_response = input.npc_response
  } else if (input.event_type === 'wake_request') {
    player_text = input.player_text
  } else if (input.event_type === 'silence_timeout') {
    silence_seconds = Math.round(input.silence_ms / 1000)
  }

  const turns = input.recent_turns ?? []
  const recent_turns = turns
    .map((t) => `- ${t.speaker}: ${t.text}`)
    .join('\n')

  return {
    player_level,
    player_text,
    npc_response,
    silence_seconds,
    recent_turns,
  }
}

export class PromptBuilder {
  private systemCache: string | null = null
  private templateCache: Map<Trigger, string> = new Map()

  async build(trigger: Trigger, input: CoachInput): Promise<PromptBundle> {
    const [system, template] = await Promise.all([
      this.getSystemPrompt(),
      this.getTemplate(trigger),
    ])

    const context = buildContextFromInput(input)
    const user = renderTemplate(template, {
      player_level: context.player_level,
      player_text: context.player_text,
      npc_response: context.npc_response,
      silence_seconds: String(context.silence_seconds),
      recent_turns: context.recent_turns,
    })

    return { system, user }
  }

  private async getSystemPrompt(): Promise<string> {
    if (this.systemCache === null) {
      this.systemCache = await readFile(join(PROMPTS_DIR, 'system.txt'), 'utf-8')
    }
    return this.systemCache
  }

  private async getTemplate(trigger: Trigger): Promise<string> {
    let cached = this.templateCache.get(trigger)
    if (cached === undefined) {
      cached = await readFile(join(PROMPTS_DIR, `context-${trigger}.txt`), 'utf-8')
      this.templateCache.set(trigger, cached)
    }
    return cached
  }

  /** For testing: clear cached prompts */
  clearCache(): void {
    this.systemCache = null
    this.templateCache.clear()
  }
}
