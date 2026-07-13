import type { CoachResponse } from '../types/coach-events.js'
import type { Trigger } from './prompt-builder.js'

/**
 * Minimal fallback templates used when the LLM call fails or times out.
 * Each trigger gets a generic, safe response that maintains the 小飞猫 persona.
 */
export const FALLBACK_TEMPLATES: Record<Trigger, CoachResponse> = {
  wake: {
    text: '喵~ 小飞猫来啦！有什么可以帮你的吗？试试说：Can you help me?',
    emotion: 'encourage',
    repeat_phrase: 'Can you help me?',
    should_tts: true,
    ttl_ms: 8000,
  },
  silence: {
    text: '喵~ 想不出来也没关系，慢慢来！可以试试说：I need help.',
    emotion: 'encourage',
    repeat_phrase: 'I need help.',
    should_tts: true,
    ttl_ms: 8000,
  },
  error: {
    text: '喵~ 差一点点，再试一次！仔细听听 NPC 是怎么说的，然后跟着说一遍。',
    emotion: 'encourage',
    should_tts: true,
    ttl_ms: 8000,
  },
}

export function getFallback(trigger: Trigger): CoachResponse {
  return { ...FALLBACK_TEMPLATES[trigger] }
}
