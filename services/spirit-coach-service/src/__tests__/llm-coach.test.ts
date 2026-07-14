import { describe, expect, it, vi } from 'vitest'
import { LLMCoach, resolveLLMBaseURL } from '../services/llm-coach.js'
import type { CoachInput } from '../types/coach-events.js'

function makeDialogueInput(overrides: Partial<CoachInput> = {}): CoachInput {
  return {
    event_type: 'dialogue_turn',
    session_id: 's1',
    user_id: 'u1',
    npc_id: 'n1',
    player_text: 'I am go to school',
    npc_response: 'Good try!',
    language: 'en',
    timestamp: Date.now(),
    player_level: 'A1',
    recent_turns: [],
    ...overrides,
  } as CoachInput
}

function createMockOpenAI(response: object) {
  return {
    chat: {
      completions: {
        create: vi.fn().mockResolvedValue({
          choices: [{ message: { content: JSON.stringify(response) } }],
        }),
      },
    },
  } as unknown as any
}

describe('resolveLLMBaseURL', () => {
  it('prefers explicit options baseURL over env vars', () => {
    const originalCoach = process.env.COACH_LLM_BASE_URL
    const originalOpenAI = process.env.OPENAI_BASE_URL
    process.env.COACH_LLM_BASE_URL = 'https://coach.example/v1'
    process.env.OPENAI_BASE_URL = 'https://openai.example/v1'

    try {
      expect(resolveLLMBaseURL('https://explicit.example/v1')).toBe('https://explicit.example/v1')
    } finally {
      restoreEnv('COACH_LLM_BASE_URL', originalCoach)
      restoreEnv('OPENAI_BASE_URL', originalOpenAI)
    }
  })

  it('prefers COACH_LLM_BASE_URL over OPENAI_BASE_URL', () => {
    const originalCoach = process.env.COACH_LLM_BASE_URL
    const originalOpenAI = process.env.OPENAI_BASE_URL
    process.env.COACH_LLM_BASE_URL = 'https://coach.example/v1'
    process.env.OPENAI_BASE_URL = 'https://openai.example/v1'

    try {
      expect(resolveLLMBaseURL()).toBe('https://coach.example/v1')
    } finally {
      restoreEnv('COACH_LLM_BASE_URL', originalCoach)
      restoreEnv('OPENAI_BASE_URL', originalOpenAI)
    }
  })

  it('falls back to OPENAI_BASE_URL', () => {
    const originalCoach = process.env.COACH_LLM_BASE_URL
    const originalOpenAI = process.env.OPENAI_BASE_URL
    delete process.env.COACH_LLM_BASE_URL
    process.env.OPENAI_BASE_URL = 'https://openai.example/v1'

    try {
      expect(resolveLLMBaseURL()).toBe('https://openai.example/v1')
    } finally {
      restoreEnv('COACH_LLM_BASE_URL', originalCoach)
      restoreEnv('OPENAI_BASE_URL', originalOpenAI)
    }
  })

  it('returns undefined when no base URL is configured', () => {
    const originalCoach = process.env.COACH_LLM_BASE_URL
    const originalOpenAI = process.env.OPENAI_BASE_URL
    delete process.env.COACH_LLM_BASE_URL
    delete process.env.OPENAI_BASE_URL

    try {
      expect(resolveLLMBaseURL()).toBeUndefined()
    } finally {
      restoreEnv('COACH_LLM_BASE_URL', originalCoach)
      restoreEnv('OPENAI_BASE_URL', originalOpenAI)
    }
  })
})

function restoreEnv(name: string, value: string | undefined): void {
  if (value === undefined) {
    delete process.env[name]
  } else {
    process.env[name] = value
  }
}

describe('LLMCoach', () => {
  it('throws at construction if OPENAI_API_KEY is missing and no DI openai', async () => {
    const original = process.env.OPENAI_API_KEY
    delete process.env.OPENAI_API_KEY

    try {
      expect(() => new LLMCoach()).toThrow('OPENAI_API_KEY')
    } finally {
      if (original !== undefined) process.env.OPENAI_API_KEY = original
    }
  })

  it('calls OpenAI with correct parameters', async () => {
    const mockResponse = {
      text: '喵~ 差一点点！正确的说法是 I am going 或者 I go。',
      emotion: 'encourage',
      repeat_phrase: 'I am going',
      should_tts: true,
      ttl_ms: 8000,
    }
    const mockOpenAI = createMockOpenAI(mockResponse)

    const coach = new LLMCoach({ openai: mockOpenAI as any, model: 'gpt-4o-mini' })
    const input = makeDialogueInput()
    const result = await coach.generate(input, 'error')

    expect(mockOpenAI.chat.completions.create).toHaveBeenCalledTimes(1)
    const callArgs = (mockOpenAI.chat.completions.create as any).mock.calls[0][0]
    expect(callArgs.model).toBe('gpt-4o-mini')
    expect(callArgs.messages[0].role).toBe('system')
    expect(callArgs.messages[0].content).toContain('小飞猫')
    expect(callArgs.messages[1].role).toBe('user')
    expect(callArgs.messages[1].content).toContain('I am go to school')
    expect(callArgs.response_format).toEqual({ type: 'json_object' })

    expect(result.text).toBe(mockResponse.text)
    expect(result.emotion).toBe('encourage')
    expect(result.repeat_phrase).toBe('I am going')
  })

  it('parses LLM JSON response', async () => {
    const mockResponse = {
      text: '喵~ 想不出来也没关系，可以试试说：I need help.',
      emotion: 'encourage',
      should_tts: true,
      ttl_ms: 8000,
    }
    const mockOpenAI = createMockOpenAI(mockResponse)

    const coach = new LLMCoach({ openai: mockOpenAI as any })
    const input = makeDialogueInput({ event_type: 'silence_timeout', silence_ms: 15000 } as any)
    const result = await coach.generate(input, 'silence')

    expect(result.text).toContain('试试说')
    expect(result.emotion).toBe('encourage')
    expect(result.should_tts).toBe(true)
  })

  it('throws on empty LLM response', async () => {
    const mockOpenAI = {
      chat: {
        completions: {
          create: vi.fn().mockResolvedValue({
            choices: [{ message: { content: null } }],
          }),
        },
      },
    } as any

    const coach = new LLMCoach({ openai: mockOpenAI })
    const input = makeDialogueInput()

    await expect(coach.generate(input, 'error')).rejects.toThrow('Empty LLM response')
  })

  it('throws on invalid JSON from LLM', async () => {
    const mockOpenAI = {
      chat: {
        completions: {
          create: vi.fn().mockResolvedValue({
            choices: [{ message: { content: 'not valid json' } }],
          }),
        },
      },
    } as any

    const coach = new LLMCoach({ openai: mockOpenAI })
    const input = makeDialogueInput()

    await expect(coach.generate(input, 'error')).rejects.toThrow('Invalid JSON')
  })

  it('throws on schema validation failure (text too short)', async () => {
    const mockOpenAI = createMockOpenAI({
      text: 'too short',
      emotion: 'encourage',
      should_tts: true,
      ttl_ms: 8000,
    })

    const coach = new LLMCoach({ openai: mockOpenAI as any })
    const input = makeDialogueInput()

    await expect(coach.generate(input, 'error')).rejects.toThrow()
  })

  it('throws on invalid emotion value', async () => {
    const mockOpenAI = createMockOpenAI({
      text: 'A reasonable length text that is long enough to pass validation check here.',
      emotion: 'angry', // invalid
      should_tts: true,
      ttl_ms: 8000,
    })

    const coach = new LLMCoach({ openai: mockOpenAI as any })
    const input = makeDialogueInput()

    await expect(coach.generate(input, 'error')).rejects.toThrow()
  })

  it('times out when LLM takes too long', async () => {
    const mockOpenAI = {
      chat: {
        completions: {
          create: vi.fn().mockImplementation(
            () => new Promise((resolve) => setTimeout(resolve, 2000))
          ),
        },
      },
    } as any

    const coach = new LLMCoach({ openai: mockOpenAI, timeoutMs: 100 })
    const input = makeDialogueInput()

    await expect(coach.generate(input, 'error')).rejects.toThrow('LLM timeout')
  }, 5000)

  it('uses COACH_LLM_MODEL env var when set', async () => {
    const original = process.env.COACH_LLM_MODEL
    process.env.COACH_LLM_MODEL = 'gpt-4o'

    try {
      const mockOpenAI = createMockOpenAI({
        text: 'A long enough text response for validation to pass properly here.',
        emotion: 'encourage',
        should_tts: true,
        ttl_ms: 8000,
      })

      const coach = new LLMCoach({ openai: mockOpenAI as any })
      const input = makeDialogueInput()
      await coach.generate(input, 'error')

      const callArgs = (mockOpenAI.chat.completions.create as any).mock.calls[0][0]
      expect(callArgs.model).toBe('gpt-4o')
    } finally {
      if (original === undefined) {
        delete process.env.COACH_LLM_MODEL
      } else {
        process.env.COACH_LLM_MODEL = original
      }
    }
  })
})
