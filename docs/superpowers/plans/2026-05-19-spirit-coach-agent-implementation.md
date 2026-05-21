# Spirit Coach Agent Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the MVP Spirit Coach closed loop so dialogue turns, 15-second silence events, and wake requests become non-blocking real-time coach hints in Godot.

**Architecture:** Keep the coach path fully asynchronous. `dialogue-service` and Godot publish normalized `coach.input` events to Redis, `spirit-coach-service` classifies and filters them with a small policy layer, then writes `coach.intervention` and pushes the same payload over a WebSocket channel to Godot. The Godot client only renders the overlay and optional TTS, so NPC dialogue continues even when the coach path fails.

**Tech Stack:** TypeScript, Fastify, ioredis, zod, vitest, Godot GDScript, Redis Streams, WebSocket.

---

## File Structure

### Files to create

- `services/spirit-coach-service/src/types/coach-events.ts` — shared coach input/output event types, priorities, zod schemas, and helper serializers for Redis/WebSocket payloads.
- `services/spirit-coach-service/src/services/trigger-classifier.ts` — classifies `dialogue_turn`, `silence_timeout`, and `wake_request` into `wake | error | silence` and reuses `ErrorDetector` for severe grammar checks.
- `services/spirit-coach-service/src/services/intervention-policy.ts` — cooldown rules, priority ordering, and final decision about whether to emit an intervention.
- `services/spirit-coach-service/src/services/coach-hint-generator.ts` — deterministic Chinese-first hint templates with one repeatable English phrase.
- `services/spirit-coach-service/src/services/coach-session-manager.ts` — stores active WebSocket clients by session and pushes `coach.intervention` payloads.
- `services/spirit-coach-service/src/routes/coach-ws.ts` — `/ws/coach` registration and connection lifecycle wiring.
- `services/spirit-coach-service/src/workers/coach-input-consumer.ts` — Redis stream consumer for `coach.input`, orchestration entry point for classifier/policy/generator/session manager.
- `services/spirit-coach-service/src/__tests__/trigger-classifier.test.ts` — unit tests for trigger classification.
- `services/spirit-coach-service/src/__tests__/intervention-policy.test.ts` — unit tests for cooldown and priority behavior.
- `services/spirit-coach-service/src/__tests__/coach-hint-generator.test.ts` — unit tests for generated hint shape and bilingual output.
- `services/spirit-coach-service/src/__tests__/coach-input-consumer.test.ts` — integration-style worker test that verifies `coach.input` becomes `coach.intervention`.
- `services/dialogue-service/src/services/coach-publisher.ts` — writes `dialogue_turn` events into Redis from the main dialogue request handler.
- `services/dialogue-service/src/__tests__/coach-publisher.test.ts` — unit test for outgoing coach event payloads.
- `apps/godot-client/assets/scripts/autoload/CoachClient.gd` — dedicated WebSocket client for `/ws/coach`, payload parsing, TTL timer, and bridge to `CoachOverlay` / TTS.

### Files to modify

- `services/spirit-coach-service/package.json` — add the Fastify WebSocket dependency if needed by the chosen plugin.
- `services/spirit-coach-service/src/index.ts` — register the WebSocket route and start the Redis consumer with the session manager.
- `services/spirit-coach-service/src/routes/coach.ts` — keep `/api/v1/coach/analyze` working while reusing the new event types where helpful.
- `services/spirit-coach-service/src/workers/message-consumer.ts` — replace or remove in favor of `coach-input-consumer.ts`; avoid duplicate consumers.
- `services/spirit-coach-service/src/services/error-detector.ts` — expose one helper that returns only high-severity errors needed by the classifier, without changing the existing analyze contract.
- `services/dialogue-service/package.json` — add `ioredis` for publishing to Redis.
- `services/dialogue-service/src/index.ts` — create a Redis-backed coach publisher once and pass it into the route registration.
- `services/dialogue-service/src/routes/dialogue.ts` — publish `dialogue_turn` after NPC response generation without blocking the HTTP reply.
- `apps/godot-client/assets/scripts/autoload/HybridAPI.gd` — add methods to publish `silence_timeout` and `wake_request` plus one helper for coach TTS if needed.
- `apps/godot-client/assets/scripts/autoload/DialogueManager.gd` — connect/disconnect the coach WebSocket during dialogue sessions and forward wake requests.
- `apps/godot-client/assets/scripts/autoload/VoicePipeline.gd` — emit a 15-second silence event hook if the existing voice code already has silence timing; otherwise expose a signal/timer seam for `DialogueManager` to use.
- `apps/godot-client/assets/scripts/components/CoachOverlay.gd` — add one small helper to hide hints after TTL if no equivalent exists already.
- `docker-compose.dev.yml` — add `spirit-coach-service` with `REDIS_URL` and port `8305`.

### Existing tests to keep green

- `services/spirit-coach-service/src/__tests__/error-detector.test.ts`
- `services/dialogue-service/src/__tests__/health.test.ts`
- `services/dialogue-service/src/__tests__/npc-engine.test.ts`

---

### Task 1: Define shared coach event types

**Files:**
- Create: `services/spirit-coach-service/src/types/coach-events.ts`
- Modify: `services/spirit-coach-service/src/routes/coach.ts`
- Test: `services/spirit-coach-service/src/__tests__/trigger-classifier.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from 'vitest'
import {
  coachInputSchema,
  coachInterventionSchema,
  interventionPriority,
} from '../types/coach-events.js'

describe('coach event schemas', () => {
  it('accepts a silence timeout input payload', () => {
    const payload = coachInputSchema.parse({
      event_type: 'silence_timeout',
      session_id: 'session-1',
      user_id: 'user-1',
      npc_id: 'npc-1',
      silence_ms: 15000,
      timestamp: 1779177600000,
    })

    expect(payload.event_type).toBe('silence_timeout')
    expect(payload.silence_ms).toBe(15000)
  })

  it('accepts an intervention payload with priority metadata', () => {
    const payload = coachInterventionSchema.parse({
      event_id: 'coach-1',
      session_id: 'session-1',
      user_id: 'user-1',
      trigger: 'wake',
      priority: interventionPriority.wake,
      text: '我来帮你！你可以说：Can you help me?',
      repeat_phrase: 'Can you help me?',
      emotion: 'encourage',
      should_tts: true,
      ttl_ms: 8000,
      timestamp: 1779177600000,
    })

    expect(payload.trigger).toBe('wake')
    expect(payload.priority).toBe(3)
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm --filter @linguaquest/spirit-coach-service test -- src/__tests__/trigger-classifier.test.ts`
Expected: FAIL with `Cannot find module '../types/coach-events.js'`.

- [ ] **Step 3: Write minimal implementation**

```ts
import { z } from 'zod'

export const interventionPriority = {
  silence: 1,
  error: 2,
  wake: 3,
} as const

const dialogueTurnSchema = z.object({
  event_type: z.literal('dialogue_turn'),
  session_id: z.string().min(1),
  user_id: z.string().min(1),
  npc_id: z.string().min(1),
  player_text: z.string().min(1),
  npc_response: z.string().min(1),
  language: z.string().min(1),
  timestamp: z.number().int(),
})

const silenceTimeoutSchema = z.object({
  event_type: z.literal('silence_timeout'),
  session_id: z.string().min(1),
  user_id: z.string().min(1),
  npc_id: z.string().min(1),
  silence_ms: z.number().int().min(15000),
  timestamp: z.number().int(),
})

const wakeRequestSchema = z.object({
  event_type: z.literal('wake_request'),
  session_id: z.string().min(1),
  user_id: z.string().min(1),
  npc_id: z.string().min(1),
  player_text: z.string().min(1),
  timestamp: z.number().int(),
})

export const coachInputSchema = z.union([
  dialogueTurnSchema,
  silenceTimeoutSchema,
  wakeRequestSchema,
])

export const coachInterventionSchema = z.object({
  event_id: z.string().min(1),
  session_id: z.string().min(1),
  user_id: z.string().min(1),
  trigger: z.enum(['wake', 'error', 'silence']),
  priority: z.number().int().min(1).max(3),
  text: z.string().min(1),
  repeat_phrase: z.string().min(1).optional(),
  emotion: z.string().min(1),
  should_tts: z.boolean(),
  ttl_ms: z.number().int().positive(),
  timestamp: z.number().int(),
})

export type CoachInput = z.infer<typeof coachInputSchema>
export type CoachIntervention = z.infer<typeof coachInterventionSchema>
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pnpm --filter @linguaquest/spirit-coach-service test -- src/__tests__/trigger-classifier.test.ts`
Expected: PASS with 2 passing assertions.

- [ ] **Step 5: Commit**

```bash
git add services/spirit-coach-service/src/types/coach-events.ts services/spirit-coach-service/src/__tests__/trigger-classifier.test.ts services/spirit-coach-service/src/routes/coach.ts
git commit -m "feat: add coach event schemas"
```

### Task 2: Build trigger classification for dialogue, silence, and wake

**Files:**
- Create: `services/spirit-coach-service/src/services/trigger-classifier.ts`
- Modify: `services/spirit-coach-service/src/services/error-detector.ts`
- Test: `services/spirit-coach-service/src/__tests__/trigger-classifier.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
import { beforeEach, describe, expect, it } from 'vitest'
import { ErrorDetector } from '../services/error-detector.js'
import { TriggerClassifier } from '../services/trigger-classifier.js'

describe('TriggerClassifier', () => {
  let classifier: TriggerClassifier

  beforeEach(() => {
    classifier = new TriggerClassifier(new ErrorDetector())
  })

  it('classifies wake requests as highest priority coach triggers', async () => {
    const result = await classifier.classify({
      event_type: 'wake_request',
      session_id: 'session-1',
      user_id: 'user-1',
      npc_id: 'npc-1',
      player_text: 'help me',
      timestamp: 1779177600000,
    })

    expect(result.trigger).toBe('wake')
    expect(result.priority).toBe(3)
  })

  it('classifies 15-second silence events as silence triggers', async () => {
    const result = await classifier.classify({
      event_type: 'silence_timeout',
      session_id: 'session-1',
      user_id: 'user-1',
      npc_id: 'npc-1',
      silence_ms: 15000,
      timestamp: 1779177600000,
    })

    expect(result.trigger).toBe('silence')
    expect(result.priority).toBe(1)
  })

  it('returns a high-severity error trigger for invalid grammar', async () => {
    const result = await classifier.classify({
      event_type: 'dialogue_turn',
      session_id: 'session-1',
      user_id: 'user-1',
      npc_id: 'npc-1',
      player_text: 'I am go to school',
      npc_response: 'Nice!',
      language: 'en',
      timestamp: 1779177600000,
    })

    expect(result.trigger).toBe('error')
    expect(result.errors[0].severity).toBe('high')
  })

  it('returns null when dialogue turn has no severe error', async () => {
    const result = await classifier.classify({
      event_type: 'dialogue_turn',
      session_id: 'session-1',
      user_id: 'user-1',
      npc_id: 'npc-1',
      player_text: 'I go to school',
      npc_response: 'Great!',
      language: 'en',
      timestamp: 1779177600000,
    })

    expect(result).toBeNull()
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm --filter @linguaquest/spirit-coach-service test -- src/__tests__/trigger-classifier.test.ts`
Expected: FAIL with `Cannot find module '../services/trigger-classifier.js'`.

- [ ] **Step 3: Write minimal implementation**

```ts
import { ErrorDetector } from './error-detector.js'
import { CoachInput, interventionPriority } from '../types/coach-events.js'

export class TriggerClassifier {
  constructor(private readonly errorDetector: ErrorDetector) {}

  async classify(input: CoachInput) {
    if (input.event_type === 'wake_request') {
      return {
        trigger: 'wake' as const,
        priority: interventionPriority.wake,
        input,
        errors: [],
      }
    }

    if (input.event_type === 'silence_timeout') {
      return {
        trigger: 'silence' as const,
        priority: interventionPriority.silence,
        input,
        errors: [],
      }
    }

    const errors = await this.errorDetector.analyze(input.player_text)
    const highSeverityErrors = errors.filter((error) => error.severity === 'high')

    if (highSeverityErrors.length === 0) {
      return null
    }

    return {
      trigger: 'error' as const,
      priority: interventionPriority.error,
      input,
      errors: highSeverityErrors,
    }
  }
}
```

Add this small helper to `ErrorDetector` if you want a named API instead of repeating the filter:

```ts
async analyzeHighSeverity(playerInput: string, expectedLevel: string = 'A1') {
  const errors = await this.analyze(playerInput, expectedLevel)
  return errors.filter((error) => error.severity === 'high')
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pnpm --filter @linguaquest/spirit-coach-service test -- src/__tests__/trigger-classifier.test.ts`
Expected: PASS with 4 passing assertions.

- [ ] **Step 5: Commit**

```bash
git add services/spirit-coach-service/src/services/trigger-classifier.ts services/spirit-coach-service/src/services/error-detector.ts services/spirit-coach-service/src/__tests__/trigger-classifier.test.ts
git commit -m "feat: classify spirit coach triggers"
```

### Task 3: Add cooldown and priority policy

**Files:**
- Create: `services/spirit-coach-service/src/services/intervention-policy.ts`
- Test: `services/spirit-coach-service/src/__tests__/intervention-policy.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { InterventionPolicy } from '../services/intervention-policy.js'

class FakeRedis {
  private values = new Map<string, string>()

  async get(key: string) {
    return this.values.get(key) ?? null
  }

  async set(key: string, value: string) {
    this.values.set(key, value)
    return 'OK'
  }
}

describe('InterventionPolicy', () => {
  let redis: FakeRedis
  let policy: InterventionPolicy

  beforeEach(() => {
    redis = new FakeRedis()
    policy = new InterventionPolicy(redis as never)
  })

  it('always allows wake triggers', async () => {
    await expect(policy.shouldIntervene({ trigger: 'wake', userId: 'user-1' })).resolves.toBe(true)
  })

  it('blocks error triggers during cooldown', async () => {
    await policy.markIntervened({ trigger: 'error', userId: 'user-1' })
    await expect(policy.shouldIntervene({ trigger: 'error', userId: 'user-1' })).resolves.toBe(false)
  })

  it('blocks silence triggers during cooldown', async () => {
    await policy.markIntervened({ trigger: 'silence', userId: 'user-1' })
    await expect(policy.shouldIntervene({ trigger: 'silence', userId: 'user-1' })).resolves.toBe(false)
  })

  it('fails closed when redis throws for cooldown checks', async () => {
    const brokenPolicy = new InterventionPolicy({
      async get() {
        throw new Error('redis down')
      },
      async set() {
        throw new Error('redis down')
      },
    } as never)

    await expect(brokenPolicy.shouldIntervene({ trigger: 'error', userId: 'user-1' })).resolves.toBe(false)
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm --filter @linguaquest/spirit-coach-service test -- src/__tests__/intervention-policy.test.ts`
Expected: FAIL with `Cannot find module '../services/intervention-policy.js'`.

- [ ] **Step 3: Write minimal implementation**

```ts
const cooldownSeconds = {
  error: 20,
  silence: 30,
} as const

export class InterventionPolicy {
  constructor(private readonly redis: { get(key: string): Promise<string | null>; set(key: string, value: string, mode?: string, ttlKey?: string, ttl?: number): Promise<unknown> }) {}

  async shouldIntervene({ trigger, userId }: { trigger: 'wake' | 'error' | 'silence'; userId: string }) {
    if (trigger === 'wake') {
      return true
    }

    try {
      const value = await this.redis.get(this.cooldownKey(trigger, userId))
      return value === null
    } catch {
      return false
    }
  }

  async markIntervened({ trigger, userId }: { trigger: 'wake' | 'error' | 'silence'; userId: string }) {
    if (trigger === 'wake') {
      return
    }

    await this.redis.set(
      this.cooldownKey(trigger, userId),
      '1',
      'EX',
      cooldownSeconds[trigger]
    )
  }

  private cooldownKey(trigger: 'error' | 'silence', userId: string) {
    return `cooldown:${userId}:spirit:${trigger}`
  }
}
```

If your Redis mock cannot support the `EX` arguments, adapt the fake to accept extra arguments instead of weakening the production API.

- [ ] **Step 4: Run test to verify it passes**

Run: `pnpm --filter @linguaquest/spirit-coach-service test -- src/__tests__/intervention-policy.test.ts`
Expected: PASS with 4 passing assertions.

- [ ] **Step 5: Commit**

```bash
git add services/spirit-coach-service/src/services/intervention-policy.ts services/spirit-coach-service/src/__tests__/intervention-policy.test.ts
git commit -m "feat: add spirit coach cooldown policy"
```

### Task 4: Generate deterministic bilingual coach hints

**Files:**
- Create: `services/spirit-coach-service/src/services/coach-hint-generator.ts`
- Test: `services/spirit-coach-service/src/__tests__/coach-hint-generator.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from 'vitest'
import { CoachHintGenerator } from '../services/coach-hint-generator.js'

describe('CoachHintGenerator', () => {
  const generator = new CoachHintGenerator()

  it('creates a Chinese-first correction hint with repeat phrase', () => {
    const hint = generator.generate({
      trigger: 'error',
      errors: [
        {
          type: 'grammar',
          severity: 'high',
          original_text: 'I am go',
          correction: 'I am going',
          explanation: 'Use present continuous for something happening now.',
        },
      ],
    })

    expect(hint.text).toContain('可以说')
    expect(hint.repeat_phrase).toBe('I am going')
    expect(hint.should_tts).toBe(true)
  })

  it('creates a silence hint for 15-second pauses', () => {
    const hint = generator.generate({ trigger: 'silence', errors: [] })
    expect(hint.text).toContain('想不出来也没关系')
    expect(hint.repeat_phrase).toBe('I need help.')
  })

  it('creates a wake hint that responds immediately', () => {
    const hint = generator.generate({ trigger: 'wake', errors: [] })
    expect(hint.text).toContain('我来帮你')
    expect(hint.repeat_phrase).toBe('Can you help me?')
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm --filter @linguaquest/spirit-coach-service test -- src/__tests__/coach-hint-generator.test.ts`
Expected: FAIL with `Cannot find module '../services/coach-hint-generator.js'`.

- [ ] **Step 3: Write minimal implementation**

```ts
import { DetectedError } from './error-detector.js'

export class CoachHintGenerator {
  generate({ trigger, errors }: { trigger: 'wake' | 'error' | 'silence'; errors: DetectedError[] }) {
    if (trigger === 'wake') {
      return {
        text: '我来帮你！你可以说：Can you help me?',
        repeat_phrase: 'Can you help me?',
        emotion: 'encourage',
        should_tts: true,
        ttl_ms: 8000,
      }
    }

    if (trigger === 'silence') {
      return {
        text: '想不出来也没关系，可以试试说：I need help.',
        repeat_phrase: 'I need help.',
        emotion: 'neutral',
        should_tts: true,
        ttl_ms: 8000,
      }
    }

    const firstError = errors[0]
    return {
      text: `差一点点！可以说：${firstError.correction}`,
      repeat_phrase: firstError.correction,
      emotion: 'encourage',
      should_tts: true,
      ttl_ms: 8000,
    }
  }
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pnpm --filter @linguaquest/spirit-coach-service test -- src/__tests__/coach-hint-generator.test.ts`
Expected: PASS with 3 passing assertions.

- [ ] **Step 5: Commit**

```bash
git add services/spirit-coach-service/src/services/coach-hint-generator.ts services/spirit-coach-service/src/__tests__/coach-hint-generator.test.ts
git commit -m "feat: add spirit coach hint generator"
```

### Task 5: Consume `coach.input` and emit `coach.intervention`

**Files:**
- Create: `services/spirit-coach-service/src/workers/coach-input-consumer.ts`
- Modify: `services/spirit-coach-service/src/workers/message-consumer.ts`
- Test: `services/spirit-coach-service/src/__tests__/coach-input-consumer.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it, vi } from 'vitest'
import { CoachInputConsumer } from '../workers/coach-input-consumer.js'
import { ErrorDetector } from '../services/error-detector.js'
import { TriggerClassifier } from '../services/trigger-classifier.js'
import { InterventionPolicy } from '../services/intervention-policy.js'
import { CoachHintGenerator } from '../services/coach-hint-generator.js'

class FakeRedis {
  inputMessages = [
    [
      'coach.input',
      [
        [
          '1710000000-0',
          [
            'event_type', 'wake_request',
            'session_id', 'session-1',
            'user_id', 'user-1',
            'npc_id', 'npc-1',
            'player_text', 'help me',
            'timestamp', '1779177600000',
          ],
        ],
      ],
    ],
  ]
  added: Array<{ stream: string; values: Record<string, string> }> = []

  async xread() {
    return this.inputMessages
  }

  async xadd(stream: string, _id: string, ...pairs: string[]) {
    const values: Record<string, string> = {}
    for (let i = 0; i < pairs.length; i += 2) {
      values[pairs[i]] = pairs[i + 1]
    }
    this.added.push({ stream, values })
    return '1710000001-0'
  }

  async xdel() {
    return 1
  }

  async get() {
    return null
  }

  async set() {
    return 'OK'
  }
}

describe('CoachInputConsumer', () => {
  it('writes a wake intervention to coach.intervention', async () => {
    const redis = new FakeRedis()
    const policy = new InterventionPolicy(redis as never)
    const classifier = new TriggerClassifier(new ErrorDetector())
    const generator = new CoachHintGenerator()
    const sessionManager = { push: vi.fn().mockResolvedValue(undefined) }

    const consumer = new CoachInputConsumer(redis as never, classifier, policy, generator, sessionManager as never)
    await consumer.consumeOnce()

    expect(redis.added).toHaveLength(1)
    expect(redis.added[0].stream).toBe('coach.intervention')
    expect(redis.added[0].values.trigger).toBe('wake')
    expect(sessionManager.push).toHaveBeenCalledTimes(1)
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm --filter @linguaquest/spirit-coach-service test -- src/__tests__/coach-input-consumer.test.ts`
Expected: FAIL with `Cannot find module '../workers/coach-input-consumer.js'`.

- [ ] **Step 3: Write minimal implementation**

```ts
import { randomUUID } from 'node:crypto'
import { coachInputSchema } from '../types/coach-events.js'

export class CoachInputConsumer {
  constructor(
    private readonly redis: {
      xread(...args: unknown[]): Promise<unknown>
      xadd(stream: string, id: string, ...pairs: string[]): Promise<string>
      xdel(stream: string, id: string): Promise<number>
    },
    private readonly classifier: { classify(input: ReturnType<typeof coachInputSchema.parse>): Promise<any> },
    private readonly policy: { shouldIntervene(arg: { trigger: 'wake' | 'error' | 'silence'; userId: string }): Promise<boolean>; markIntervened(arg: { trigger: 'wake' | 'error' | 'silence'; userId: string }): Promise<void> },
    private readonly generator: { generate(arg: { trigger: 'wake' | 'error' | 'silence'; errors: any[] }): { text: string; repeat_phrase?: string; emotion: string; should_tts: boolean; ttl_ms: number } },
    private readonly sessionManager: { push(sessionId: string, payload: Record<string, unknown>): Promise<void> }
  ) {}

  async consumeOnce() {
    const result = await this.redis.xread('COUNT', 1, 'BLOCK', 1, 'STREAMS', 'coach.input', '0') as [string, [string, string[]][]][] | null
    if (!result) {
      return
    }

    for (const [, messages] of result) {
      for (const [messageId, raw] of messages) {
        const data: Record<string, unknown> = {}
        for (let i = 0; i < raw.length; i += 2) {
          const key = raw[i]
          const value = raw[i + 1]
          data[key] = key === 'timestamp' || key === 'silence_ms' ? Number(value) : value
        }

        const input = coachInputSchema.parse(data)
        const classified = await this.classifier.classify(input)
        if (classified === null) {
          await this.redis.xdel('coach.input', messageId)
          continue
        }

        const allowed = await this.policy.shouldIntervene({
          trigger: classified.trigger,
          userId: input.user_id,
        })

        if (!allowed) {
          await this.redis.xdel('coach.input', messageId)
          continue
        }

        const hint = this.generator.generate({
          trigger: classified.trigger,
          errors: classified.errors,
        })

        const payload = {
          event_id: randomUUID(),
          session_id: input.session_id,
          user_id: input.user_id,
          trigger: classified.trigger,
          priority: classified.priority,
          text: hint.text,
          repeat_phrase: hint.repeat_phrase,
          emotion: hint.emotion,
          should_tts: hint.should_tts,
          ttl_ms: hint.ttl_ms,
          timestamp: Date.now(),
        }

        const pairs = Object.entries(payload)
          .filter(([, value]) => value !== undefined)
          .flatMap(([key, value]) => [key, String(value)])

        await this.redis.xadd('coach.intervention', '*', ...pairs)
        await this.policy.markIntervened({ trigger: classified.trigger, userId: input.user_id })
        await this.sessionManager.push(input.session_id, payload)
        await this.redis.xdel('coach.input', messageId)
      }
    }
  }
}
```

If `message-consumer.ts` becomes fully obsolete after this task, delete it in the same commit instead of leaving two worker entry points.

- [ ] **Step 4: Run test to verify it passes**

Run: `pnpm --filter @linguaquest/spirit-coach-service test -- src/__tests__/coach-input-consumer.test.ts`
Expected: PASS with 1 passing assertion.

- [ ] **Step 5: Commit**

```bash
git add services/spirit-coach-service/src/workers/coach-input-consumer.ts services/spirit-coach-service/src/__tests__/coach-input-consumer.test.ts services/spirit-coach-service/src/workers/message-consumer.ts
git commit -m "feat: consume coach events from redis"
```

### Task 6: Expose `/ws/coach` and wire the coach service runtime

**Files:**
- Create: `services/spirit-coach-service/src/services/coach-session-manager.ts`
- Create: `services/spirit-coach-service/src/routes/coach-ws.ts`
- Modify: `services/spirit-coach-service/package.json`
- Modify: `services/spirit-coach-service/src/index.ts`
- Test: `services/spirit-coach-service/src/__tests__/coach-input-consumer.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it, vi } from 'vitest'
import { CoachSessionManager } from '../services/coach-session-manager.js'

describe('CoachSessionManager', () => {
  it('pushes payloads to the matching session connection', async () => {
    const sent: string[] = []
    const socket = { send: vi.fn((message: string) => sent.push(message)) }
    const manager = new CoachSessionManager()

    manager.attach('session-1', socket as never)
    await manager.push('session-1', { trigger: 'wake', text: 'hello' })

    expect(socket.send).toHaveBeenCalledTimes(1)
    expect(sent[0]).toContain('wake')
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm --filter @linguaquest/spirit-coach-service test -- src/__tests__/coach-input-consumer.test.ts`
Expected: FAIL with `Cannot find module '../services/coach-session-manager.js'` or missing websocket registration.

- [ ] **Step 3: Write minimal implementation**

Add the dependency in `services/spirit-coach-service/package.json`:

```json
{
  "dependencies": {
    "@fastify/cors": "^9.0.0",
    "@fastify/websocket": "^10.0.1",
    "@supabase/supabase-js": "^2.43.0",
    "fastify": "^4.28.0",
    "ioredis": "^5.4.0",
    "zod": "^3.23.0"
  }
}
```

Create the session manager:

```ts
export class CoachSessionManager {
  private readonly sessions = new Map<string, { send(message: string): void }>()

  attach(sessionId: string, socket: { send(message: string): void }) {
    this.sessions.set(sessionId, socket)
  }

  detach(sessionId: string) {
    this.sessions.delete(sessionId)
  }

  async push(sessionId: string, payload: Record<string, unknown>) {
    const socket = this.sessions.get(sessionId)
    if (!socket) {
      return
    }

    socket.send(JSON.stringify(payload))
  }
}
```

Create the route:

```ts
import { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { CoachSessionManager } from '../services/coach-session-manager.js'

const querySchema = z.object({
  session_id: z.string().min(1),
})

export async function registerCoachWsRoute(app: FastifyInstance, sessionManager: CoachSessionManager) {
  app.get('/ws/coach', { websocket: true }, (connection, request) => {
    const query = querySchema.parse(request.query)
    sessionManager.attach(query.session_id, connection.socket)

    connection.socket.on('close', () => {
      sessionManager.detach(query.session_id)
    })
  })
}
```

Wire `src/index.ts`:

```ts
import websocket from '@fastify/websocket'
import Redis from 'ioredis'
import { CoachSessionManager } from './services/coach-session-manager.js'
import { TriggerClassifier } from './services/trigger-classifier.js'
import { InterventionPolicy } from './services/intervention-policy.js'
import { CoachHintGenerator } from './services/coach-hint-generator.js'
import { CoachInputConsumer } from './workers/coach-input-consumer.js'
import { registerCoachWsRoute } from './routes/coach-ws.js'
import { ErrorDetector } from './services/error-detector.js'

const redisUrl = process.env.REDIS_URL ?? 'redis://localhost:6380'
const redis = new Redis(redisUrl)
const sessionManager = new CoachSessionManager()

app.register(websocket)
app.register(async (instance) => {
  await registerCoachWsRoute(instance, sessionManager)
})

const consumer = new CoachInputConsumer(
  redis,
  new TriggerClassifier(new ErrorDetector()),
  new InterventionPolicy(redis),
  new CoachHintGenerator(),
  sessionManager,
)

if (process.env.NODE_ENV !== 'test') {
  start()
  setInterval(() => {
    void consumer.consumeOnce().catch((error) => app.log.error(error))
  }, 200)
}
```

Keep the loop simple for MVP. Do not add a job framework unless the current codebase already uses one.

- [ ] **Step 4: Run test to verify it passes**

Run: `pnpm --filter @linguaquest/spirit-coach-service test`
Expected: PASS including existing `error-detector` tests and the new session manager test.

- [ ] **Step 5: Commit**

```bash
git add services/spirit-coach-service/package.json services/spirit-coach-service/src/index.ts services/spirit-coach-service/src/services/coach-session-manager.ts services/spirit-coach-service/src/routes/coach-ws.ts services/spirit-coach-service/src/__tests__/coach-input-consumer.test.ts
git commit -m "feat: push coach interventions over websocket"
```

### Task 7: Publish dialogue turns from `dialogue-service`

**Files:**
- Create: `services/dialogue-service/src/services/coach-publisher.ts`
- Modify: `services/dialogue-service/package.json`
- Modify: `services/dialogue-service/src/index.ts`
- Modify: `services/dialogue-service/src/routes/dialogue.ts`
- Test: `services/dialogue-service/src/__tests__/coach-publisher.test.ts`

- [ ] **Step 1: Write the failing test**

```ts
import { describe, expect, it } from 'vitest'
import { CoachPublisher } from '../services/coach-publisher.js'

class FakeRedis {
  calls: Array<{ stream: string; pairs: string[] }> = []

  async xadd(stream: string, id: string, ...pairs: string[]) {
    this.calls.push({ stream, pairs })
    return '1710000001-0'
  }
}

describe('CoachPublisher', () => {
  it('publishes dialogue_turn events to coach.input', async () => {
    const redis = new FakeRedis()
    const publisher = new CoachPublisher(redis as never)

    await publisher.publishDialogueTurn({
      session_id: 'session-1',
      user_id: 'anonymous',
      npc_id: 'npc-1',
      player_text: 'I am go to school',
      npc_response: 'Nice try!',
      language: 'en',
      timestamp: 1779177600000,
    })

    expect(redis.calls).toHaveLength(1)
    expect(redis.calls[0].stream).toBe('coach.input')
    expect(redis.calls[0].pairs).toContain('event_type')
    expect(redis.calls[0].pairs).toContain('dialogue_turn')
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm --filter @linguaquest/dialogue-service test -- src/__tests__/coach-publisher.test.ts`
Expected: FAIL with `Cannot find module '../services/coach-publisher.js'`.

- [ ] **Step 3: Write minimal implementation**

Add `ioredis` to `services/dialogue-service/package.json` dependencies.

Create the publisher:

```ts
export class CoachPublisher {
  constructor(private readonly redis: { xadd(stream: string, id: string, ...pairs: string[]): Promise<string> }) {}

  async publishDialogueTurn(payload: {
    session_id: string
    user_id: string
    npc_id: string
    player_text: string
    npc_response: string
    language: string
    timestamp: number
  }) {
    await this.redis.xadd(
      'coach.input',
      '*',
      'event_type', 'dialogue_turn',
      'session_id', payload.session_id,
      'user_id', payload.user_id,
      'npc_id', payload.npc_id,
      'player_text', payload.player_text,
      'npc_response', payload.npc_response,
      'language', payload.language,
      'timestamp', String(payload.timestamp),
    )
  }
}
```

Wire `src/index.ts` with one Redis client:

```ts
import Redis from 'ioredis'
import { CoachPublisher } from './services/coach-publisher.js'

const redisUrl = process.env.REDIS_URL ?? 'redis://localhost:6380'
const coachPublisher = new CoachPublisher(new Redis(redisUrl))

app.register(async (instance) => {
  await registerDialogueRoutes(instance, coachPublisher)
})
```

Modify the route signature and publish after the NPC result is available:

```ts
export async function registerDialogueRoutes(app: FastifyInstance, coachPublisher: CoachPublisher) {
  const npcEngine = new NPCEngine()

  app.post('/api/v1/dialogue', async (request, reply) => {
    const body = dialogueSchema.parse(request.body)
    const userId = 'anonymous'

    const result = await npcEngine.processDialogue(
      {
        ...body,
        user_id: userId,
        cefr_level: 'A1',
      },
      npcProfile,
      [],
    )

    void coachPublisher.publishDialogueTurn({
      session_id: body.session_id,
      user_id: userId,
      npc_id: body.npc_id,
      player_text: body.player_input,
      npc_response: result.npc_text,
      language: body.language,
      timestamp: Date.now(),
    }).catch((error) => app.log.error(error))

    return reply.send(result)
  })
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pnpm --filter @linguaquest/dialogue-service test -- src/__tests__/coach-publisher.test.ts && pnpm --filter @linguaquest/dialogue-service test -- src/__tests__/npc-engine.test.ts`
Expected: PASS for the new publisher test and the existing NPC engine test.

- [ ] **Step 5: Commit**

```bash
git add services/dialogue-service/package.json services/dialogue-service/src/index.ts services/dialogue-service/src/routes/dialogue.ts services/dialogue-service/src/services/coach-publisher.ts services/dialogue-service/src/__tests__/coach-publisher.test.ts
git commit -m "feat: publish dialogue turns for spirit coach"
```

### Task 8: Add Godot WebSocket coach client and overlay flow

**Files:**
- Create: `apps/godot-client/assets/scripts/autoload/CoachClient.gd`
- Modify: `apps/godot-client/assets/scripts/autoload/HybridAPI.gd`
- Modify: `apps/godot-client/assets/scripts/autoload/DialogueManager.gd`
- Modify: `apps/godot-client/assets/scripts/components/CoachOverlay.gd`
- Test: manual Godot validation

- [ ] **Step 1: Add the smallest failing manual check**

Open the game, start an NPC dialogue, and try to locate a running coach connection. Expected today: there is no `/ws/coach` client and no coach overlay event path, so nothing happens.

- [ ] **Step 2: Run the failing manual check**

Run: start the backend stack, then launch the Godot client and enter a dialogue.
Expected: FAIL in the sense that no coach hint appears for any backend-sent intervention.

- [ ] **Step 3: Write minimal implementation**

Create `CoachClient.gd`:

```gdscript
extends Node

const COACH_WS_URL = "ws://localhost:8305/ws/coach"

signal intervention_received(payload: Dictionary)
signal connection_error(message: String)

var socket := WebSocketPeer.new()
var session_id: String = ""
var connected := false

func connect_for_session(next_session_id: String) -> void:
	session_id = next_session_id
	var url = COACH_WS_URL + "?session_id=" + session_id.uri_encode()
	var err = socket.connect_to_url(url)
	if err != OK:
		connection_error.emit("Coach websocket connect failed: " + str(err))

func disconnect_socket() -> void:
	if connected:
		socket.close()
	connected = false

func _process(_delta: float) -> void:
	if socket.get_ready_state() == WebSocketPeer.STATE_CLOSED:
		connected = false
		return

	socket.poll()
	if socket.get_ready_state() == WebSocketPeer.STATE_OPEN:
		connected = true

	while socket.get_available_packet_count() > 0:
		var packet = socket.get_packet().get_string_from_utf8()
		var payload = JSON.parse_string(packet)
		if payload is Dictionary:
			intervention_received.emit(payload)
```

Add a helper in `CoachOverlay.gd`:

```gdscript
func show_hint_for_duration(text: String, emotion: String, ttl_ms: int) -> void:
	show_hint(text, emotion)
	await get_tree().create_timer(float(ttl_ms) / 1000.0).timeout
	hide_hint()
```

Wire `DialogueManager.gd`:

```gdscript
func _ready() -> void:
	HybridAPI.asr_received.connect(_on_asr_received)
	HybridAPI.dialogue_received.connect(_on_dialogue_received)
	HybridAPI.tts_received.connect(_on_tts_received)
	VoicePipeline.voice_ended.connect(_on_voice_ended)
	CoachClient.intervention_received.connect(_on_coach_intervention)

func start_npc_dialogue(npc_id: String, greeting: String) -> void:
	...
	CoachClient.connect_for_session("dialogue-" + str(Time.get_unix_time_from_system()))

func end_dialogue() -> void:
	...
	CoachClient.disconnect_socket()

func _on_coach_intervention(payload: Dictionary) -> void:
	CoachOverlay.show_hint_for_duration(
		payload.get("text", ""),
		payload.get("emotion", "neutral"),
		payload.get("ttl_ms", 8000)
	)
	if payload.get("should_tts", false):
		HybridAPI.synthesize_tts(payload.get("repeat_phrase", payload.get("text", "")), "spirit", GameManager.current_lang)
```

If the session id already exists elsewhere in Godot, use that existing source instead of inventing a second session id.

- [ ] **Step 4: Run the manual check to verify it passes**

Run: launch the stack and Godot client again, then inject a sample payload through the backend or Redis.
Expected: coach bubble appears, hides after TTL, and optional TTS plays without interrupting NPC dialogue.

- [ ] **Step 5: Commit**

```bash
git add apps/godot-client/assets/scripts/autoload/CoachClient.gd apps/godot-client/assets/scripts/autoload/HybridAPI.gd apps/godot-client/assets/scripts/autoload/DialogueManager.gd apps/godot-client/assets/scripts/components/CoachOverlay.gd
git commit -m "feat: show spirit coach interventions in godot"
```

### Task 9: Publish silence timeout and wake requests from Godot

**Files:**
- Modify: `apps/godot-client/assets/scripts/autoload/HybridAPI.gd`
- Modify: `apps/godot-client/assets/scripts/autoload/DialogueManager.gd`
- Modify: `apps/godot-client/assets/scripts/autoload/VoicePipeline.gd`
- Test: manual Godot validation

- [ ] **Step 1: Add the smallest failing manual check**

Start a dialogue, stay silent for 15 seconds, then say `help me`. Expected today: neither action publishes a coach event.

- [ ] **Step 2: Run the failing manual check**

Run: launch Godot, begin an NPC dialogue, stay silent, then ask for help.
Expected: FAIL in the sense that no coach response appears for silence or wake.

- [ ] **Step 3: Write minimal implementation**

In `HybridAPI.gd`, add two helpers:

```gdscript
func publish_coach_silence_timeout(session_id: String, npc_id: String, silence_ms: int) -> void:
	var body = JSON.stringify({
		"event_type": "silence_timeout",
		"session_id": session_id,
		"user_id": "anonymous",
		"npc_id": npc_id,
		"silence_ms": silence_ms,
		"timestamp": Time.get_unix_time_from_system() * 1000,
	})
	var headers = ["Content-Type: application/json"]
	http_request.request("http://localhost:8305/api/v1/coach/events", headers, HTTPClient.METHOD_POST, body)

func publish_coach_wake_request(session_id: String, npc_id: String, player_text: String) -> void:
	var body = JSON.stringify({
		"event_type": "wake_request",
		"session_id": session_id,
		"user_id": "anonymous",
		"npc_id": npc_id,
		"player_text": player_text,
		"timestamp": Time.get_unix_time_from_system() * 1000,
	})
	var headers = ["Content-Type: application/json"]
	http_request.request("http://localhost:8305/api/v1/coach/events", headers, HTTPClient.METHOD_POST, body)
```

In `DialogueManager.gd`, add a silence timer and a wake phrase check:

```gdscript
var coach_session_id: String = ""
var silence_timer: SceneTreeTimer

func start_npc_dialogue(npc_id: String, greeting: String) -> void:
	coach_session_id = "dialogue-" + str(Time.get_unix_time_from_system())
	...
	_reset_silence_watch()

func _reset_silence_watch() -> void:
	silence_timer = get_tree().create_timer(15.0)
	silence_timer.timeout.connect(_on_silence_timeout)

func _on_silence_timeout() -> void:
	if dialogue_state == "active":
		HybridAPI.publish_coach_silence_timeout(coach_session_id, current_npc_id, 15000)

func _on_voice_ended(audio_data: PackedByteArray) -> void:
	...
	if _is_wake_request(result.user_text):
		HybridAPI.publish_coach_wake_request(coach_session_id, current_npc_id, result.user_text)
	_reset_silence_watch()

func _is_wake_request(text: String) -> bool:
	var lower = text.to_lower()
	return lower.find("help") >= 0 or lower.find("帮帮我") >= 0 or lower.find("我不会") >= 0
```

To support those POSTs, add a small HTTP route in `services/spirit-coach-service/src/routes/coach.ts`:

```ts
const coachEventSchema = coachInputSchema

app.post('/api/v1/coach/events', async (request, reply) => {
  const body = coachEventSchema.parse(request.body)
  const pairs = Object.entries(body).flatMap(([key, value]) => [key, String(value)])
  await redis.xadd('coach.input', '*', ...pairs)
  return reply.send({ success: true })
})
```

Pass the shared Redis client into `registerCoachRoutes` instead of constructing route-local state.

- [ ] **Step 4: Run the manual check to verify it passes**

Run: launch the stack and Godot client again. Stay silent for 15 seconds, then say `help me`.
Expected: silence produces an encouragement hint, and wake phrase produces an immediate help hint.

- [ ] **Step 5: Commit**

```bash
git add apps/godot-client/assets/scripts/autoload/HybridAPI.gd apps/godot-client/assets/scripts/autoload/DialogueManager.gd apps/godot-client/assets/scripts/autoload/VoicePipeline.gd services/spirit-coach-service/src/routes/coach.ts
git commit -m "feat: publish silence and wake events for spirit coach"
```

### Task 10: Wire local runtime and verify the golden path end to end

**Files:**
- Modify: `docker-compose.dev.yml`
- Test: manual runtime validation across services and Godot

- [ ] **Step 1: Add the failing runtime check**

Bring up Redis, dialogue-service, voice-service, and spirit-coach-service together. Expected today: `docker-compose.dev.yml` has no `spirit-coach-service`, so the full closed loop cannot run.

- [ ] **Step 2: Run the failing runtime check**

Run: `docker compose -f docker-compose.dev.yml up --build redis dialogue-service voice-service`
Expected: FAIL for the full feature because there is no spirit coach service container.

- [ ] **Step 3: Write minimal implementation**

Add this service block to `docker-compose.dev.yml`:

```yaml
  spirit-coach-service:
    build: ./services/spirit-coach-service
    ports: ["8305:8305"]
    environment:
      REDIS_URL: redis://redis:6379
    depends_on: [redis]
```

Keep the rest of the compose file unchanged.

- [ ] **Step 4: Run the golden-path verification**

Run these checks in order:

1. `docker compose -f docker-compose.dev.yml up --build redis dialogue-service spirit-coach-service`
   Expected: both services log healthy startup.
2. `pnpm --filter @linguaquest/spirit-coach-service test`
   Expected: PASS.
3. `pnpm --filter @linguaquest/dialogue-service test`
   Expected: PASS.
4. Launch the Godot client and verify these manual flows:
   - speak `I am go to school` → coach correction appears
   - wait 15 seconds during active dialogue → encouragement hint appears
   - say `help me` or `帮帮我` → immediate wake hint appears
   - stop `spirit-coach-service` while keeping dialogue-service up → NPC dialogue still works, only coach hints disappear

- [ ] **Step 5: Commit**

```bash
git add docker-compose.dev.yml
git commit -m "chore: wire spirit coach service into dev stack"
```

---

## Self-Review

### Spec coverage

- Three trigger types (`error`, `silence`, `wake`) are implemented in Tasks 2, 7, 8, and 9.
- Redis input/output streams (`coach.input`, `coach.intervention`) are implemented in Tasks 5, 7, and 9.
- WebSocket push to Godot is implemented in Tasks 6 and 8.
- Chinese-first deterministic hints with one English phrase are implemented in Task 4.
- Cooldown and priority ordering (`wake > error > silence`) are implemented in Tasks 2 and 3.
- Non-blocking failure behavior is preserved by asynchronous publish/push wiring in Tasks 5, 7, 8, and 10.
- Manual validation for the golden path and degraded path is covered in Tasks 8, 9, and 10.

### Placeholder scan

No `TBD`, `TODO`, “similar to above”, or unspecified “write tests for this” placeholders remain. Every code-writing step includes concrete code blocks and commands.

### Type consistency

- Event names are consistently `dialogue_turn`, `silence_timeout`, and `wake_request`.
- Intervention triggers are consistently `wake`, `error`, and `silence`.
- Shared fields are consistently named `session_id`, `user_id`, `npc_id`, `player_text`, `timestamp`, `repeat_phrase`, and `ttl_ms`.
- Priority mapping stays `wake = 3`, `error = 2`, `silence = 1` throughout the plan.

Plan complete and saved to `docs/superpowers/plans/2026-05-19-spirit-coach-agent-implementation.md`. Two execution options:

1. Subagent-Driven (recommended) - I dispatch a fresh subagent per task, review between tasks, fast iteration

2. Inline Execution - Execute tasks in this session using executing-plans, batch execution with checkpoints

Which approach?
