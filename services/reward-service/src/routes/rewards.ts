import { FastifyInstance } from 'fastify'
import { z } from 'zod'
import { DropEngine } from '../services/drop-engine.js'
import { UserStateManager } from '../services/user-state-manager.js'
import { AchievementEngine, DEFAULT_ACHIEVEMENTS } from '../services/achievement-engine.js'

// ── Request Schemas ──────────────────────────────────────────────

const dropSchema = z.object({
  quest_type: z.enum(['main', 'side', 'daily']),
  cefr_level: z.string().default('A1'),
})

const grantXPBodySchema = z.object({
  user_id: z.string(),
  amount: z.number().min(1).max(10000),
  source: z.string().optional().default('manual'),
})

const grantBadgeBodySchema = z.object({
  user_id: z.string(),
  badge_id: z.string(),
  badge_name: z.string().optional(),
  badge_description: z.string().optional(),
  badge_icon: z.string().optional(),
  source: z.string().optional().default('manual'),
})

const grantAreaBodySchema = z.object({
  user_id: z.string(),
  area_id: z.string(),
  area_name: z.string().optional(),
  source: z.string().optional().default('manual'),
})

const questCompleteBodySchema = z.object({
  user_id: z.string(),
  quest_id: z.string(),
  quest_type: z.enum(['main', 'side', 'daily']),
  cefr_level: z.string().default('A1'),
})

// ── Route Registration ───────────────────────────────────────────

export async function registerRewardRoutes(app: FastifyInstance) {
  const dropEngine = new DropEngine()
  const userState = new UserStateManager()
  const achievementEngine = new AchievementEngine(userState)

  // ── Drop Engine (existing) ───────────────────────────────────

  app.post('/api/v1/rewards/roll', async (request, reply) => {
    const body = dropSchema.parse(request.body)
    const drop = await dropEngine.calculateDrop(
      'anonymous',
      body.quest_type,
      body.cefr_level,
    )
    return reply.send(drop)
  })

  app.get('/api/v1/rewards/inventory', async (_request, reply) => {
    return reply.send([
      { item_id: 'item_1', name: '铜币', rarity: 'common', equipped: false },
      { item_id: 'item_2', name: '银币', rarity: 'rare', equipped: true },
    ])
  })

  // ── XP Grant ─────────────────────────────────────────────────

  app.post('/api/v1/rewards/grant-xp', async (request, reply) => {
    const body = grantXPBodySchema.parse(request.body)
    const result = userState.addXP(body.user_id, body.amount)

    // Check achievements after XP gain
    const unlocks = achievementEngine.checkAll(body.user_id)

    const state = userState.getState(body.user_id)
    return reply.send({
      user_state: state,
      xp_result: result,
      source: body.source,
      achievements_unlocked: unlocks,
    })
  })

  // ── Badge Grant ──────────────────────────────────────────────

  app.post('/api/v1/rewards/grant-badge', async (request, reply) => {
    const body = grantBadgeBodySchema.parse(request.body)
    const isNew = userState.addBadge(body.user_id, body.badge_id)

    // Check achievements after badge gain
    const unlocks = achievementEngine.checkAll(body.user_id)

    const state = userState.getState(body.user_id)
    return reply.send({
      user_state: state,
      is_new_badge: isNew,
      source: body.source,
      achievements_unlocked: unlocks,
    })
  })

  // ── Area Unlock ──────────────────────────────────────────────

  app.post('/api/v1/rewards/unlock-area', async (request, reply) => {
    const body = grantAreaBodySchema.parse(request.body)
    const isNew = userState.unlockArea(body.user_id, body.area_id)

    // Check achievements after area unlock
    const unlocks = achievementEngine.checkAll(body.user_id)

    const state = userState.getState(body.user_id)
    return reply.send({
      user_state: state,
      is_new_area: isNew,
      source: body.source,
      achievements_unlocked: unlocks,
    })
  })

  // ── Quest Complete (triggers drop + XP) ──────────────────────

  app.post('/api/v1/rewards/quest-complete', async (request, reply) => {
    const body = questCompleteBodySchema.parse(request.body)

    // 1. Roll drop
    const drop = await dropEngine.calculateDrop(
      body.user_id,
      body.quest_type,
      body.cefr_level,
    )

    // 2. Grant XP based on quest type
    const xpAmounts: Record<string, number> = { main: 50, side: 30, daily: 20 }
    const xpAmount = xpAmounts[body.quest_type] ?? 20
    const xpResult = userState.addXP(body.user_id, xpAmount)

    // 3. Check achievements
    const unlocks = achievementEngine.checkAll(body.user_id)

    const state = userState.getState(body.user_id)
    return reply.send({
      drop,
      user_state: state,
      xp_result: xpResult,
      achievements_unlocked: unlocks,
    })
  })

  // ── User State ───────────────────────────────────────────────

  app.get('/api/v1/rewards/state/:userId', async (request, reply) => {
    const { userId } = request.params as { userId: string }
    const state = userState.getUserState(userId)
    if (!state) {
      return reply.code(404).send({ error: 'User not found', user_id: userId })
    }
    return reply.send(state)
  })

  // ── Achievements ─────────────────────────────────────────────

  app.get('/api/v1/achievements', async (_request, reply) => {
    const achievements = achievementEngine.getAll(false)
    return reply.send({ achievements })
  })

  app.get('/api/v1/achievements/:userId', async (request, reply) => {
    const { userId } = request.params as { userId: string }
    const achievements = achievementEngine.getAll(false)
    const userProgress = achievementEngine.getUserAchievements(userId)

    return reply.send({
      achievements,
      user_progress: userProgress,
    })
  })

  app.get('/api/v1/achievements/:userId/:achievementId', async (request, reply) => {
    const { userId, achievementId } = request.params as { userId: string; achievementId: string }
    const achievement = achievementEngine.getById(achievementId)
    if (!achievement) {
      return reply.code(404).send({ error: 'Achievement not found' })
    }

    // Reveal hidden achievements only if completed
    if (achievement.is_hidden) {
      const progress = achievementEngine.getUserAchievement(userId, achievementId)
      if (!progress?.is_completed) {
        return reply.code(404).send({ error: 'Achievement not found' })
      }
    }

    const userProgress = achievementEngine.getUserAchievement(userId, achievementId)
    const state = userState.getUserState(userId)
    const calculatedProgress = state
      ? achievementEngine.calculateProgress(achievement, state)
      : 0

    return reply.send({
      achievement,
      user_progress: userProgress ?? {
        user_id: userId,
        achievement_id: achievementId,
        progress: calculatedProgress,
        is_completed: false,
        completed_at: null,
        reward_grant_id: null,
      },
    })
  })

  // ── Achievement Stats ────────────────────────────────────────

  app.get('/api/v1/achievements/stats/:userId', async (request, reply) => {
    const { userId } = request.params as { userId: string }
    const userProgress = achievementEngine.getUserAchievements(userId)
    const completed = userProgress.filter((p) => p.is_completed).length
    const total = achievementEngine.getAll(false).length

    return reply.send({
      user_id: userId,
      completed,
      total,
      completion_rate: total > 0 ? (completed / total) * 100 : 0,
    })
  })
}
