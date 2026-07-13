import { z } from 'zod'

export const interventionPriority = {
  silence: 1,
  error: 2,
  wake: 3,
} as const

const playerLevelSchema = z.enum(['A1', 'A2', 'B1', 'B2']).default('A1')

const recentTurnSchema = z.object({
  speaker: z.enum(['player', 'npc']),
  text: z.string(),
})

const recentTurnsSchema = z.array(recentTurnSchema).default([])

const dialogueTurnSchema = z.object({
  event_type: z.literal('dialogue_turn'),
  session_id: z.string().min(1),
  user_id: z.string().min(1),
  npc_id: z.string().min(1),
  player_text: z.string().min(1),
  npc_response: z.string().min(1),
  language: z.string().min(1),
  timestamp: z.number(),
  player_level: playerLevelSchema,
  recent_turns: recentTurnsSchema,
})

const silenceTimeoutSchema = z.object({
  event_type: z.literal('silence_timeout'),
  session_id: z.string().min(1),
  user_id: z.string().min(1),
  npc_id: z.string().min(1),
  silence_ms: z.number().int().min(15000),
  timestamp: z.number(),
  player_level: playerLevelSchema,
  recent_turns: recentTurnsSchema,
})

const wakeRequestSchema = z.object({
  event_type: z.literal('wake_request'),
  session_id: z.string().min(1),
  user_id: z.string().min(1),
  npc_id: z.string().min(1),
  player_text: z.string().min(1),
  timestamp: z.number(),
  player_level: playerLevelSchema,
  recent_turns: recentTurnsSchema,
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
  timestamp: z.number(),
})

export const coachResponseSchema = z.object({
  text: z.string().min(30).max(300),
  emotion: z.enum(['encourage', 'neutral', 'celebrate']),
  repeat_phrase: z.string().optional(),
  should_tts: z.boolean(),
  ttl_ms: z.number().int().positive().default(8000),
})

export type CoachInput = z.infer<typeof coachInputSchema>
export type CoachIntervention = z.infer<typeof coachInterventionSchema>
export type CoachResponse = z.infer<typeof coachResponseSchema>
export type PlayerLevel = z.infer<typeof playerLevelSchema>
export type RecentTurn = z.infer<typeof recentTurnSchema>
