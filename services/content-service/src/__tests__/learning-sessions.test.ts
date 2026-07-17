import { beforeEach, expect, test } from 'vitest'
import app from '../index.js'

async function startLearningSession() {
  const res = await app.inject({
    method: 'POST',
    url: '/api/v1/learning-sessions/start',
    payload: {
      child_id: 'child-001',
      scene_id: 'spirit_forest',
      task_id: 'say-hello'
    }
  })

  expect(res.statusCode).toBe(201)
  return res.json().session
}

beforeEach(async () => {
  await app.inject({ method: 'POST', url: '/api/v1/learning-sessions/test/reset' })
})

test('POST /api/v1/learning-sessions/start creates an active game session and initial timeline events', async () => {
  const res = await app.inject({
    method: 'POST',
    url: '/api/v1/learning-sessions/start',
    payload: {
      child_id: 'child-001',
      scene_id: 'spirit_forest',
      task_id: 'say-hello'
    }
  })

  expect(res.statusCode).toBe(201)
  const body = res.json()

  expect(body.session).toMatchObject({
    child_id: 'child-001',
    scene_id: 'spirit_forest',
    current_task_id: 'say-hello',
    status: 'active'
  })
  expect(body.session.session_id).toEqual(expect.any(String))
  expect(body.timeline_events).toEqual([
    expect.objectContaining({
      event_type: 'session_started',
      session_id: body.session.session_id
    }),
    expect.objectContaining({
      event_type: 'scene_entered',
      session_id: body.session.session_id,
      payload: {
        scene_id: 'spirit_forest',
        task_id: 'say-hello'
      }
    })
  ])
})

test('POST /api/v1/learning-sessions/:sessionId/prompt-turns stores a prompt turn content snapshot', async () => {
  const session = await startLearningSession()

  const res = await app.inject({
    method: 'POST',
    url: `/api/v1/learning-sessions/${session.session_id}/prompt-turns`,
    payload: {
      scene_id: 'spirit_forest',
      task_id: 'say-hello',
      prompt_text: 'Say: Hello, forest spirit!',
      target_phrases: ['Hello, forest spirit!'],
      answer_type: 'spoken_phrase',
      scoring_rule_version: 'magic-echo-v1'
    }
  })

  expect(res.statusCode).toBe(201)
  expect(res.json().prompt_turn).toMatchObject({
    session_id: session.session_id,
    turn_number: 1,
    scene_id: 'spirit_forest',
    task_id: 'say-hello',
    prompt_text: 'Say: Hello, forest spirit!',
    target_phrases: ['Hello, forest spirit!'],
    answer_type: 'spoken_phrase',
    scoring_rule_version: 'magic-echo-v1'
  })
})

async function createPromptTurn(sessionId: string) {
  const res = await app.inject({
    method: 'POST',
    url: `/api/v1/learning-sessions/${sessionId}/prompt-turns`,
    payload: {
      scene_id: 'spirit_forest',
      task_id: 'say-hello',
      prompt_text: 'Say: Hello, forest spirit!',
      target_phrases: ['Hello, forest spirit!'],
      answer_type: 'spoken_phrase',
      scoring_rule_version: 'magic-echo-v1'
    }
  })

  expect(res.statusCode).toBe(201)
  return res.json().prompt_turn
}

test('POST /api/v1/learning-sessions/:sessionId/attempts records interaction attempts idempotently by local key', async () => {
  const session = await startLearningSession()
  const promptTurn = await createPromptTurn(session.session_id)

  const payload = {
    prompt_turn_id: promptTurn.prompt_turn_id,
    local_idempotency_key: 'local-attempt-001',
    answer_text: 'Hello, forest spirit!',
    input_mode: 'text'
  }
  const first = await app.inject({
    method: 'POST',
    url: `/api/v1/learning-sessions/${session.session_id}/attempts`,
    payload
  })
  const second = await app.inject({
    method: 'POST',
    url: `/api/v1/learning-sessions/${session.session_id}/attempts`,
    payload
  })

  expect(first.statusCode).toBe(201)
  expect(second.statusCode).toBe(200)
  expect(second.json().interaction_attempt).toEqual(first.json().interaction_attempt)
})

test('GET /api/v1/learning-sessions/:sessionId returns structured session timeline with turns and attempts', async () => {
  const session = await startLearningSession()
  const promptTurn = await createPromptTurn(session.session_id)

  await app.inject({
    method: 'POST',
    url: `/api/v1/learning-sessions/${session.session_id}/attempts`,
    payload: {
      prompt_turn_id: promptTurn.prompt_turn_id,
      local_idempotency_key: 'local-attempt-001',
      answer_text: 'Hello, forest spirit!',
      input_mode: 'text'
    }
  })

  const res = await app.inject({
    method: 'GET',
    url: `/api/v1/learning-sessions/${session.session_id}`
  })

  expect(res.statusCode).toBe(200)
  expect(res.json()).toMatchObject({
    session: {
      session_id: session.session_id,
      status: 'active'
    },
    prompt_turns: [
      {
        prompt_turn_id: promptTurn.prompt_turn_id,
        attempts: [
          {
            local_idempotency_key: 'local-attempt-001',
            answer_text: 'Hello, forest spirit!',
            input_mode: 'text'
          }
        ]
      }
    ],
    timeline_events: [
      { event_type: 'session_started', sequence: 1 },
      { event_type: 'scene_entered', sequence: 2 }
    ]
  })
})

test('POST /api/v1/learning-sessions/start reuses active session for the same child', async () => {
  const first = await startLearningSession()
  const second = await app.inject({
    method: 'POST',
    url: '/api/v1/learning-sessions/start',
    payload: {
      child_id: 'child-001',
      scene_id: 'spell_library',
      task_id: 'find-book'
    }
  })

  expect(second.statusCode).toBe(200)
  expect(second.json().session.session_id).toBe(first.session_id)
  expect(second.json().timeline_events).toHaveLength(3)
  expect(second.json().timeline_events[2]).toMatchObject({
    event_type: 'scene_entered',
    sequence: 3,
    payload: {
      scene_id: 'spell_library',
      task_id: 'find-book'
    }
  })
})
