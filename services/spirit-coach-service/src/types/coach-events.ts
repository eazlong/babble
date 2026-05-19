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
