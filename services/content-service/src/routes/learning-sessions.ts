import type { FastifyInstance, FastifyReply } from 'fastify'
import { randomUUID } from 'node:crypto'

type GameSessionStatus = 'active' | 'completed'

type GameSession = {
  session_id: string
  child_id: string
  scene_id: string
  current_task_id: string
  status: GameSessionStatus
  started_at: string
}

type TimelineEvent = {
  event_id: string
  session_id: string
  event_type: string
  payload: Record<string, unknown>
  sequence: number
  created_at: string
}

type PromptTurn = {
  prompt_turn_id: string
  session_id: string
  turn_number: number
  scene_id: string
  task_id: string
  prompt_text: string
  target_phrases: string[]
  answer_type: string
  scoring_rule_version: string
  created_at: string
}

type InteractionAttempt = {
  interaction_attempt_id: string
  session_id: string
  prompt_turn_id: string
  local_idempotency_key: string
  answer_text: string
  input_mode: string
  created_at: string
}

type Store = {
  sessions: GameSession[]
  timelineEvents: TimelineEvent[]
  promptTurns: PromptTurn[]
  interactionAttempts: InteractionAttempt[]
}

function createEmptyStore(): Store {
  return {
    sessions: [],
    timelineEvents: [],
    promptTurns: [],
    interactionAttempts: []
  }
}

let store = createEmptyStore()

function isObjectBody(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null && !Array.isArray(value)
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0
}

function getRequiredString(
  body: Record<string, unknown>,
  field: string,
  reply: FastifyReply
): string | undefined {
  const value = body[field]
  if (!isNonEmptyString(value)) {
    reply.status(400).send({ error: `${field} is required` })
    return undefined
  }
  return value
}

function getRequiredStringArray(
  body: Record<string, unknown>,
  field: string,
  reply: FastifyReply
): string[] | undefined {
  const value = body[field]
  if (!Array.isArray(value) || value.length === 0 || !value.every(isNonEmptyString)) {
    reply.status(400).send({ error: `${field} must contain non-empty strings` })
    return undefined
  }
  return value
}

function getRequestBody(value: unknown, reply: FastifyReply): Record<string, unknown> | undefined {
  if (!isObjectBody(value)) {
    reply.status(400).send({ error: 'request body must be an object' })
    return undefined
  }
  return value
}

function createTimelineEvent(
  sessionId: string,
  eventType: string,
  payload: Record<string, unknown>,
  sequence: number
): TimelineEvent {
  return {
    event_id: randomUUID(),
    session_id: sessionId,
    event_type: eventType,
    payload,
    sequence,
    created_at: new Date().toISOString()
  }
}

function resetLearningSessionStore() {
  store = createEmptyStore()
}

export async function registerLearningSessionRoutes(app: FastifyInstance) {
  if (process.env.NODE_ENV === 'test') {
    app.post('/api/v1/learning-sessions/test/reset', async () => {
      resetLearningSessionStore()
      return { ok: true }
    })
  }

  app.post('/api/v1/learning-sessions/start', async (request, reply) => {
    const body = getRequestBody(request.body, reply)
    if (!body) return reply

    const childId = getRequiredString(body, 'child_id', reply)
    if (!childId) return reply
    const sceneId = getRequiredString(body, 'scene_id', reply)
    if (!sceneId) return reply
    const taskId = getRequiredString(body, 'task_id', reply)
    if (!taskId) return reply

    const existingSession = store.sessions.find(
      session => session.child_id === childId && session.status === 'active'
    )

    if (existingSession) {
      const updatedSession = {
        ...existingSession,
        scene_id: sceneId,
        current_task_id: taskId
      }
      const sceneEnteredEvent = createTimelineEvent(
        updatedSession.session_id,
        'scene_entered',
        { scene_id: sceneId, task_id: taskId },
        store.timelineEvents.filter(event => event.session_id === updatedSession.session_id).length + 1
      )
      const sessions = store.sessions.map(session =>
        session.session_id === updatedSession.session_id ? updatedSession : session
      )
      const timelineEvents = [...store.timelineEvents, sceneEnteredEvent]
      store = {
        ...store,
        sessions,
        timelineEvents
      }

      return reply.status(200).send({
        session: updatedSession,
        timeline_events: timelineEvents.filter(event => event.session_id === updatedSession.session_id)
      })
    }

    const session: GameSession = {
      session_id: randomUUID(),
      child_id: childId,
      scene_id: sceneId,
      current_task_id: taskId,
      status: 'active',
      started_at: new Date().toISOString()
    }
    const timelineEvents = [
      createTimelineEvent(session.session_id, 'session_started', { child_id: childId }, 1),
      createTimelineEvent(session.session_id, 'scene_entered', { scene_id: sceneId, task_id: taskId }, 2)
    ]

    store = {
      ...store,
      sessions: [...store.sessions, session],
      timelineEvents: [...store.timelineEvents, ...timelineEvents]
    }

    return reply.status(201).send({
      session,
      timeline_events: timelineEvents
    })
  })

  app.post('/api/v1/learning-sessions/:sessionId/prompt-turns', async (request, reply) => {
    const { sessionId } = request.params as { sessionId: string }
    const body = getRequestBody(request.body, reply)
    if (!body) return reply

    const session = store.sessions.find(item => item.session_id === sessionId)
    if (!session) {
      return reply.status(404).send({ error: 'Learning session not found' })
    }

    const sceneId = getRequiredString(body, 'scene_id', reply)
    if (!sceneId) return reply
    const taskId = getRequiredString(body, 'task_id', reply)
    if (!taskId) return reply
    const promptText = getRequiredString(body, 'prompt_text', reply)
    if (!promptText) return reply
    const targetPhrases = getRequiredStringArray(body, 'target_phrases', reply)
    if (!targetPhrases) return reply
    const answerType = getRequiredString(body, 'answer_type', reply)
    if (!answerType) return reply
    const scoringRuleVersion = getRequiredString(body, 'scoring_rule_version', reply)
    if (!scoringRuleVersion) return reply

    const promptTurn: PromptTurn = {
      prompt_turn_id: randomUUID(),
      session_id: session.session_id,
      turn_number: store.promptTurns.filter(turn => turn.session_id === session.session_id).length + 1,
      scene_id: sceneId,
      task_id: taskId,
      prompt_text: promptText,
      target_phrases: targetPhrases,
      answer_type: answerType,
      scoring_rule_version: scoringRuleVersion,
      created_at: new Date().toISOString()
    }

    store = {
      ...store,
      promptTurns: [...store.promptTurns, promptTurn]
    }

    return reply.status(201).send({ prompt_turn: promptTurn })
  })

  app.post('/api/v1/learning-sessions/:sessionId/attempts', async (request, reply) => {
    const { sessionId } = request.params as { sessionId: string }
    const body = getRequestBody(request.body, reply)
    if (!body) return reply

    const session = store.sessions.find(item => item.session_id === sessionId)
    if (!session) {
      return reply.status(404).send({ error: 'Learning session not found' })
    }

    const promptTurnId = getRequiredString(body, 'prompt_turn_id', reply)
    if (!promptTurnId) return reply
    const localIdempotencyKey = getRequiredString(body, 'local_idempotency_key', reply)
    if (!localIdempotencyKey) return reply
    const answerText = getRequiredString(body, 'answer_text', reply)
    if (!answerText) return reply
    const inputMode = getRequiredString(body, 'input_mode', reply)
    if (!inputMode) return reply

    const promptTurn = store.promptTurns.find(
      turn => turn.session_id === session.session_id && turn.prompt_turn_id === promptTurnId
    )
    if (!promptTurn) {
      return reply.status(404).send({ error: 'Prompt turn not found' })
    }

    const existingAttempt = store.interactionAttempts.find(
      attempt =>
        attempt.session_id === session.session_id &&
        attempt.local_idempotency_key === localIdempotencyKey
    )
    if (existingAttempt) {
      return reply.status(200).send({ interaction_attempt: existingAttempt })
    }

    const interactionAttempt: InteractionAttempt = {
      interaction_attempt_id: randomUUID(),
      session_id: session.session_id,
      prompt_turn_id: promptTurn.prompt_turn_id,
      local_idempotency_key: localIdempotencyKey,
      answer_text: answerText,
      input_mode: inputMode,
      created_at: new Date().toISOString()
    }

    store = {
      ...store,
      interactionAttempts: [...store.interactionAttempts, interactionAttempt]
    }

    return reply.status(201).send({ interaction_attempt: interactionAttempt })
  })

  app.get('/api/v1/learning-sessions/:sessionId', async (request, reply) => {
    const { sessionId } = request.params as { sessionId: string }
    const session = store.sessions.find(item => item.session_id === sessionId)

    if (!session) {
      return reply.status(404).send({ error: 'Learning session not found' })
    }

    const promptTurns = store.promptTurns
      .filter(turn => turn.session_id === session.session_id)
      .sort((a, b) => a.turn_number - b.turn_number)
      .map(turn => ({
        ...turn,
        attempts: store.interactionAttempts.filter(
          attempt => attempt.prompt_turn_id === turn.prompt_turn_id
        )
      }))
    const timelineEvents = store.timelineEvents
      .filter(event => event.session_id === session.session_id)
      .sort((a, b) => a.sequence - b.sequence)

    return {
      session,
      prompt_turns: promptTurns,
      timeline_events: timelineEvents
    }
  })
}
