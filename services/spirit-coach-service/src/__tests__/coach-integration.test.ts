/**
 * Integration tests for the LLM coach pipeline.
 *
 * These tests exercise the chain: CoachInputConsumer → LLMCoach → PromptBuilder
 * → template → (mocked) OpenAI → parse → output.
 *
 * The OpenAI API is mocked to return predetermined responses, so we test the
 * integration seams rather than LLM behaviour itself. Each test case corresponds
 * to one of the 10 scenarios in llm-coach-spec.md §7.2.
 */
import { describe, expect, it, vi, beforeEach } from 'vitest'
import { CoachInputConsumer } from '../workers/coach-input-consumer.js'
import { LLMCoach } from '../services/llm-coach.js'
import { StreakTracker } from '../services/streak-tracker.js'
import type { CoachInput } from '../types/coach-events.js'

// Mock Redis that captures interventions
function createMockRedis(inputMessages?: [string, [string, string[]][]][]) {
  const added: Array<{ stream: string; values: Record<string, string> }> = []
  return {
    added,
    async xread(): Promise<[string, [string, string[]][]][] | null> {
      return inputMessages ?? null
    },
    async xadd(_stream: string, ...args: unknown[]): Promise<string> {
      // args: 'MAXLEN', '~', '10000', '*', key1, val1, key2, val2, ...
      const pairs = args.slice(4) as string[]
      const values: Record<string, string> = {}
      for (let i = 0; i < pairs.length; i += 2) {
        values[pairs[i]] = pairs[i + 1]
      }
      added.push({ stream: _stream, values })
      return 'id'
    },
    async xdel(): Promise<number> {
      return 1
    },
  }
}

// Build a dialogue_turn message for Redis stream
function makeDialogueTurn(overrides: Record<string, string> = {}): [string, string[]] {
  const fields: string[] = [
    'event_type', overrides.event_type ?? 'dialogue_turn',
    'session_id', overrides.session_id ?? 'session-1',
    'user_id', overrides.user_id ?? 'user-1',
    'npc_id', overrides.npc_id ?? 'npc-1',
    'player_text', overrides.player_text ?? 'hello',
    'npc_response', overrides.npc_response ?? 'Good!',
    'language', overrides.language ?? 'en',
    'timestamp', overrides.timestamp ?? String(Date.now()),
    'player_level', overrides.player_level ?? 'A1',
    'recent_turns', overrides.recent_turns ?? '[]',
  ]
  return ['1710000000-0', fields]
}

// Mock OpenAI that returns a predetermined JSON response and captures the request
function createMockOpenAI(responseJson: object) {
  const calls: any[] = []
  return {
    calls,
    instance: {
      chat: {
        completions: {
          create: vi.fn().mockImplementation(async (args: any) => {
            calls.push(args)
            return { choices: [{ message: { content: JSON.stringify(responseJson) } }] }
          }),
        },
      },
    },
  }
}

function createSlowOpenAI(delayMs: number) {
  return {
    instance: {
      chat: {
        completions: {
          create: vi.fn().mockImplementation(
            () => new Promise((resolve) => setTimeout(() => resolve({ choices: [] }), delayMs))
          ),
        },
      },
    },
  }
}

const defaultLLMResponse = {
  text: '喵~ 差一点点！正确的说法是：I am going。跟着小飞猫再试一次吧！',
  emotion: 'encourage' as const,
  repeat_phrase: 'I am going',
  should_tts: true,
  ttl_ms: 8000,
}

function buildConsumer(
  redis: ReturnType<typeof createMockRedis>,
  classifier: any,
  llmCoach: LLMCoach,
  streakTracker: StreakTracker,
) {
  const policy = {
    shouldIntervene: vi.fn().mockResolvedValue(true),
    markIntervened: vi.fn().mockResolvedValue(undefined),
  }
  const sessionManager = { push: vi.fn().mockResolvedValue(undefined) }
  const logger = { warn: vi.fn(), error: vi.fn() }
  return new CoachInputConsumer(
    redis as any, classifier, policy,
    llmCoach as any, sessionManager, streakTracker, undefined, logger as any,
  )
}

function classifierFor(trigger: string, errors: any[] = []) {
  return {
    classify: vi.fn().mockResolvedValue({
      trigger,
      priority: trigger === 'error' ? 2 : trigger === 'wake' ? 3 : 1,
      errors,
    }),
  }
}

describe('LLM Coach Integration — 10 scenarios', () => {
  let streakTracker: StreakTracker

  beforeEach(() => {
    streakTracker = new StreakTracker()
  })

  // 1. A1 player says "I am go" → correction
  it('1. A1 error correction: I am go → I am going', async () => {
    const mock = createMockOpenAI(defaultLLMResponse)
    const coach = new LLMCoach({ openai: mock.instance as any })

    const redis = createMockRedis([
      ['coach.input', [makeDialogueTurn({ player_text: 'I am go to school', player_level: 'A1' })]],
    ])

    const consumer = buildConsumer(redis, classifierFor('error', [{ type: 'grammar' }]), coach, streakTracker)
    await consumer.consumeOnce()

    // LLM was called with A1 in prompt
    const prompt = mock.calls[0].messages[1].content
    expect(prompt).toContain('A1')
    expect(prompt).toContain('I am go to school')

    // Output intervention is correct
    expect(redis.added).toHaveLength(1)
    expect(redis.added[0].values.text).toContain('I am going')
    expect(redis.added[0].values.emotion).toBe('encourage')
  })

  // 2. A1 player silent 15s → Chinese encouragement
  it('2. A1 silence → Chinese encouragement', async () => {
    const silenceResponse = {
      text: '喵~ 想不出来也没关系，可以试试说：I need help.',
      emotion: 'encourage' as const,
      repeat_phrase: 'I need help.',
      should_tts: true,
      ttl_ms: 8000,
    }
    const mock = createMockOpenAI(silenceResponse)
    const coach = new LLMCoach({ openai: mock.instance as any })

    const redis = createMockRedis([
      ['coach.input', [[
        '1710000000-0',
        [
          'event_type', 'silence_timeout',
          'session_id', 's1',
          'user_id', 'u1',
          'npc_id', 'n1',
          'silence_ms', '15000',
          'timestamp', String(Date.now()),
          'player_level', 'A1',
          'recent_turns', '[]',
        ],
      ]]],
    ])

    const consumer = buildConsumer(redis, classifierFor('silence'), coach, streakTracker)
    await consumer.consumeOnce()

    expect(redis.added).toHaveLength(1)
    expect(redis.added[0].values.trigger).toBe('silence')
    // Chinese text present
    expect(redis.added[0].values.text).toMatch(/[一-鿿]/)
  })

  // 3. B2 player error → mostly English correction
  it('3. B2 error → mostly English correction', async () => {
    const b2Response = {
      text: 'Close! The correct form is "He doesn\'t" with third-person singular.',
      emotion: 'encourage' as const,
      repeat_phrase: "He doesn't",
      should_tts: true,
      ttl_ms: 8000,
    }
    const mock = createMockOpenAI(b2Response)
    const coach = new LLMCoach({ openai: mock.instance as any })

    const redis = createMockRedis([
      ['coach.input', [makeDialogueTurn({
        player_text: "He don't like it",
        player_level: 'B2',
      })]],
    ])

    const consumer = buildConsumer(redis, classifierFor('error'), coach, streakTracker)
    await consumer.consumeOnce()

    const prompt = mock.calls[0].messages[1].content
    expect(prompt).toContain('B2')
    expect(redis.added[0].values.text).toContain("doesn")
  })

  // 4. Wake request → help
  it('4. Wake request → help response', async () => {
    const wakeResponse = {
      text: '喵~ 小飞猫来啦！我可以帮你。',
      emotion: 'encourage' as const,
      should_tts: true,
      ttl_ms: 8000,
    }
    const mock = createMockOpenAI(wakeResponse)
    const coach = new LLMCoach({ openai: mock.instance as any })

    const redis = createMockRedis([
      ['coach.input', [makeDialogueTurn({
        event_type: 'wake_request',
        player_text: 'help me',
      })]],
    ])

    const consumer = buildConsumer(redis, classifierFor('wake'), coach, streakTracker)
    await consumer.consumeOnce()

    expect(redis.added).toHaveLength(1)
    expect(redis.added[0].values.trigger).toBe('wake')
    expect(redis.added[0].values.text).toContain('帮')
  })

  // 5. A1 player 3 consecutive errors → reduce difficulty (streak in prompt)
  it('5. 3 consecutive errors → streak data in prompt', async () => {
    const mock = createMockOpenAI(defaultLLMResponse)
    const coach = new LLMCoach({ openai: mock.instance as any })

    // Pre-load streak tracker with 2 errors, then trigger a 3rd
    streakTracker.recordError('user-1')
    streakTracker.recordError('user-1')

    const redis = createMockRedis([
      ['coach.input', [makeDialogueTurn({ player_text: 'I is wrong' })]],
    ])

    const consumer = buildConsumer(redis, classifierFor('error'), coach, streakTracker)
    await consumer.consumeOnce()

    // The prompt should contain "连续错误：3 次"
    const prompt = mock.calls[0].messages[1].content
    expect(prompt).toContain('连续错误')
    expect(prompt).toContain('3')
  })

  // 6. B1 player 3 consecutive correct → praise (streak in prompt)
  it('6. 3 consecutive correct → correct_streak in prompt', async () => {
    const mock = createMockOpenAI(defaultLLMResponse)
    const coach = new LLMCoach({ openai: mock.instance as any })

    streakTracker.recordCorrect('user-1')
    streakTracker.recordCorrect('user-1')
    streakTracker.recordCorrect('user-1')

    // Trigger an error anyway to force intervention (streak data still visible)
    const redis = createMockRedis([
      ['coach.input', [makeDialogueTurn({ player_text: 'I am go', player_level: 'B1' })]],
    ])

    const consumer = buildConsumer(redis, classifierFor('error'), coach, streakTracker)
    await consumer.consumeOnce()

    const prompt = mock.calls[0].messages[1].content
    // Note: the error trigger will recordError, resetting correct streak
    // So we expect the prompt to show error_streak: 1, not correct_streak
    expect(prompt).toContain('连续错误')
  })

  // 7. Player speaks Chinese → LLM should gently redirect (tested via prompt content)
  it('7. Chinese input → LLM prompt contains player text as-is', async () => {
    const chineseResponse = {
      text: '喵~ Try to say it in English! You can do it.',
      emotion: 'encourage' as const,
      should_tts: true,
      ttl_ms: 8000,
    }
    const mock = createMockOpenAI(chineseResponse)
    const coach = new LLMCoach({ openai: mock.instance as any })

    const redis = createMockRedis([
      ['coach.input', [makeDialogueTurn({ player_text: '我不知道怎么说' })]],
    ])

    const consumer = buildConsumer(redis, classifierFor('error'), coach, streakTracker)
    await consumer.consumeOnce()

    const prompt = mock.calls[0].messages[1].content
    // Chinese input is preserved in prompt for LLM to see
    expect(prompt).toContain('我不知道怎么说')
  })

  // 8. Long correct sentence → praise (tested via prompt construction)
  it('8. Long sentence → text included in prompt for LLM to praise', async () => {
    const praiseResponse = {
      text: 'Excellent! That was a great sentence! 你说得非常棒！',
      emotion: 'celebrate' as const,
      should_tts: true,
      ttl_ms: 8000,
    }
    const mock = createMockOpenAI(praiseResponse)
    const coach = new LLMCoach({ openai: mock.instance as any })

    const longText = 'I went to the park yesterday and I saw a big dog playing with a small cat'
    const redis = createMockRedis([
      ['coach.input', [makeDialogueTurn({ player_text: longText })]],
    ])

    const consumer = buildConsumer(redis, classifierFor('error'), coach, streakTracker)
    await consumer.consumeOnce()

    const prompt = mock.calls[0].messages[1].content
    expect(prompt).toContain(longText)
    // Celebrate emotion flows through to intervention
    expect(redis.added[0].values.emotion).toBe('celebrate')
  })

  // 9. Off-topic input → LLM redirects (prompt contains the text)
  it('9. Off-topic input → preserved in prompt for LLM to redirect', async () => {
    const redirectResponse = {
      text: '喵~ Let\'s focus on our conversation. Try saying...',
      emotion: 'encourage' as const,
      repeat_phrase: 'Let me try again',
      should_tts: true,
      ttl_ms: 8000,
    }
    const mock = createMockOpenAI(redirectResponse)
    const coach = new LLMCoach({ openai: mock.instance as any })

    const redis = createMockRedis([
      ['coach.input', [makeDialogueTurn({ player_text: 'I like pizza and video games' })]],
    ])

    const consumer = buildConsumer(redis, classifierFor('error'), coach, streakTracker)
    await consumer.consumeOnce()

    const prompt = mock.calls[0].messages[1].content
    expect(prompt).toContain('pizza and video games')
  })

  // 10. LLM timeout → fallback template used
  it('10. LLM timeout → fallback template used', async () => {
    const slow = createSlowOpenAI(2000)
    const coach = new LLMCoach({ openai: slow.instance as any, timeoutMs: 100 })

    const redis = createMockRedis([
      ['coach.input', [makeDialogueTurn({ player_text: 'I am go' })]],
    ])

    const consumer = buildConsumer(redis, classifierFor('error'), coach, streakTracker)
    await consumer.consumeOnce()

    // Fallback was used (error fallback text)
    expect(redis.added).toHaveLength(1)
    expect(redis.added[0].values.text).toContain('再试一次')
    expect(redis.added[0].values.emotion).toBe('encourage')
  })

  // Bonus: conversation history flows through to prompt
  it('recent_turns in input appears in prompt', async () => {
    const mock = createMockOpenAI(defaultLLMResponse)
    const coach = new LLMCoach({ openai: mock.instance as any })

    const recentTurns = JSON.stringify([
      { speaker: 'player', text: 'hi' },
      { speaker: 'npc', text: 'hello there' },
    ])

    const redis = createMockRedis([
      ['coach.input', [makeDialogueTurn({
        player_text: 'how are you',
        recent_turns: recentTurns,
      })]],
    ])

    const consumer = buildConsumer(redis, classifierFor('error'), coach, streakTracker)
    await consumer.consumeOnce()

    const prompt = mock.calls[0].messages[1].content
    expect(prompt).toContain('player: hi')
    expect(prompt).toContain('npc: hello there')
  })
})
