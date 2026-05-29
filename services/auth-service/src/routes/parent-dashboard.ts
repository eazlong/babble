import { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify'
import { z } from 'zod'
import { authenticate, authenticateWithReply } from '../middleware/auth.js'

// Zod schemas for request validation
const timeLimitSchema = z.object({
  daily_time_limit_minutes: z.number().int().min(1).max(480)
})

const contentSettingsSchema = z.object({
  scenes: z.object({
    spiritForest: z.boolean().optional(),
    spellLibrary: z.boolean().optional(),
    rainbowGarden: z.boolean().optional()
  }).optional(),
  filterLevel: z.enum(['strict', 'moderate', 'relaxed']).optional()
})

export async function registerParentDashboardRoutes(app: FastifyInstance) {
  // ============================================================
  // GET /api/v1/parent/:parentId/dashboard
  // Returns list of children with today's stats
  // ============================================================
  app.get('/api/v1/parent/:parentId/dashboard', {
    preHandler: async (request, reply) => {
      const userId = await authenticateWithReply(request, reply, app)
      if (!userId) return
      // Verify the requesting user is the parent
      const { parentId } = request.params as { parentId: string }
      if (userId !== parentId) {
        reply.status(403).send({ error: { code: 'FORBIDDEN', message: 'Not authorized to access this parent account' } })
      }
    }
  }, async (request: FastifyRequest, reply: FastifyReply) => {
    const { parentId } = request.params as { parentId: string }

    // Get all children for this parent
    const { data: children, error: childrenError } = await app.supabase
      .from('child_data.child_accounts')
      .select(`
        child_id,
        daily_time_limit_minutes,
        content_filter_level,
        users!inner(user_id, display_name, cefr_level, age_group)
      `)
      .eq('parent_id', parentId)

    if (childrenError) {
      return reply.status(500).send({ error: { code: 'QUERY_FAILED', message: childrenError.message } })
    }

    if (!children || children.length === 0) {
      return reply.send({ children: [] })
    }

    // Build dashboard data with aggregated stats for each child
    const dashboardChildren = await Promise.all(
      children.map(async (ca) => {
        const childId = ca.child_id
        const user = (ca.users as any)

        // Today's game time
        const { data: timeToday } = await app.supabase
          .from('game_sessions')
          .select('start_time, end_time')
          .eq('user_id', childId)
          .gte('start_time', new Date().toISOString().split('T')[0])

        let total_time_today = 0
        if (timeToday && timeToday.length > 0) {
          total_time_today = timeToday.reduce((sum: number, session: any) => {
            if (session.start_time && session.end_time) {
              return sum + (new Date(session.end_time).getTime() - new Date(session.start_time).getTime()) / 60000
            }
            return sum
          }, 0)
        }

        // Vocabulary count from assessment_results (per-user vocabulary assessments)
        const { count: vocabulary_count } = await app.supabase
          .from('assessment_results')
          .select('*', { count: 'exact', head: true })
          .eq('user_id', childId)

        // Quests completed
        const { data: quests } = await app.supabase
          .from('quest_progress')
          .select('status')
          .eq('user_id', childId)
          .eq('status', 'completed')

        return {
          child_id: childId,
          display_name: user?.display_name || 'Unknown',
          total_time_today: Math.round(total_time_today),
          daily_time_limit_minutes: ca.daily_time_limit_minutes,
          vocabulary_count: vocabulary_count || 0,
          cefr_level: user?.cefr_level || 'pre-A1',
          quests_completed: quests?.length || 0
        }
      })
    )

    return reply.send({ children: dashboardChildren })
  })

  // ============================================================
  // GET /api/v1/parent/:parentId/reports
  // Returns aggregated learning report
  // ============================================================
  app.get('/api/v1/parent/:parentId/reports', {
    preHandler: async (request, reply) => {
      const userId = await authenticateWithReply(request, reply, app)
      if (!userId) return
      const { parentId } = request.params as { parentId: string }
      if (userId !== parentId) {
        reply.status(403).send({ error: { code: 'FORBIDDEN', message: 'Not authorized to access this parent account' } })
      }
    }
  }, async (request: FastifyRequest, reply: FastifyReply) => {
    const { parentId } = request.params as { parentId: string }

    // Get all child IDs for this parent
    const { data: childAccounts, error: caError } = await app.supabase
      .from('child_data.child_accounts')
      .select('child_id')
      .eq('parent_id', parentId)

    if (caError) {
      return reply.status(500).send({ error: { code: 'QUERY_FAILED', message: caError.message } })
    }

    if (!childAccounts || childAccounts.length === 0) {
      return reply.send({
        total_time_today: 0,
        total_time_week: 0,
        total_time_month: 0,
        vocabulary_growth: 0,
        cefr_level: 'pre-A1',
        cefr_progress: 0,
        quests_completed: 0
      })
    }

    const childIds = childAccounts.map((ca: any) => ca.child_id)

    // Today's total time
    const todayStart = new Date()
    todayStart.setHours(0, 0, 0, 0)

    const weekStart = new Date()
    weekStart.setDate(weekStart.getDate() - 7)

    const monthStart = new Date()
    monthStart.setDate(monthStart.getDate() - 30)

    // Game sessions for today
    const { data: sessionsToday } = await app.supabase
      .from('game_sessions')
      .select('start_time, end_time')
      .in('user_id', childIds)
      .gte('start_time', todayStart.toISOString())

    let total_time_today = 0
    if (sessionsToday) {
      total_time_today = sessionsToday.reduce((sum: number, s: any) => {
        if (s.start_time && s.end_time) {
          return sum + (new Date(s.end_time).getTime() - new Date(s.start_time).getTime()) / 60000
        }
        return sum
      }, 0)
    }

    // Game sessions for week
    const { data: sessionsWeek } = await app.supabase
      .from('game_sessions')
      .select('start_time, end_time')
      .in('user_id', childIds)
      .gte('start_time', weekStart.toISOString())

    let total_time_week = 0
    if (sessionsWeek) {
      total_time_week = sessionsWeek.reduce((sum: number, s: any) => {
        if (s.start_time && s.end_time) {
          return sum + (new Date(s.end_time).getTime() - new Date(s.start_time).getTime()) / 60000
        }
        return sum
      }, 0)
    }

    // Game sessions for month
    const { data: sessionsMonth } = await app.supabase
      .from('game_sessions')
      .select('start_time, end_time')
      .in('user_id', childIds)
      .gte('start_time', monthStart.toISOString())

    let total_time_month = 0
    if (sessionsMonth) {
      total_time_month = sessionsMonth.reduce((sum: number, s: any) => {
        if (s.start_time && s.end_time) {
          return sum + (new Date(s.end_time).getTime() - new Date(s.start_time).getTime()) / 60000
        }
        return sum
      }, 0)
    }

    // Vocabulary growth (assessment_results in last 30 days)
    const { count: vocabulary_growth } = await app.supabase
      .from('assessment_results')
      .select('*', { count: 'exact', head: true })
      .in('user_id', childIds)
      .gte('assessed_at', monthStart.toISOString())

    // Get average CEFR level from first child
    const { data: usersData } = await app.supabase
      .from('users')
      .select('cefr_level')
      .in('user_id', childIds)
      .limit(1)

    const cefr_level = usersData?.[0]?.cefr_level || 'pre-A1'

    // Total quests completed
    const { data: quests } = await app.supabase
      .from('quest_progress')
      .select('status')
      .in('user_id', childIds)
      .eq('status', 'completed')

    return reply.send({
      total_time_today: Math.round(total_time_today),
      total_time_week: Math.round(total_time_week),
      total_time_month: Math.round(total_time_month),
      vocabulary_growth: vocabulary_growth || 0,
      cefr_level,
      cefr_progress: cefrProgressPercent(cefr_level),
      quests_completed: quests?.length || 0
    })
  })

  // ============================================================
  // PUT /api/v1/parent/children/:childId/time-limit
  // Update daily time limit for a child
  // ============================================================
  app.put('/api/v1/parent/children/:childId/time-limit', {
    preHandler: async (request, reply) => {
      await authenticate(request, reply, app)
    }
  }, async (request: FastifyRequest, reply: FastifyReply) => {
    const { childId } = request.params as { childId: string }
    const body = timeLimitSchema.parse(request.body)
    const { daily_time_limit_minutes } = body

    // Verify the requesting user is the parent of this child
    const userId = (request as any).userId
    const { data: link, error: linkError } = await app.supabase
      .from('child_data.child_accounts')
      .select('parent_id')
      .eq('child_id', childId)
      .single()

    if (linkError || !link) {
      return reply.status(404).send({ error: { code: 'CHILD_NOT_FOUND', message: 'Child account not found' } })
    }

    if (link.parent_id !== userId) {
      return reply.status(403).send({ error: { code: 'FORBIDDEN', message: 'Not authorized to modify this child\'s settings' } })
    }

    const { error: updateError } = await app.supabase
      .from('child_data.child_accounts')
      .update({ daily_time_limit_minutes })
      .eq('child_id', childId)

    if (updateError) {
      return reply.status(500).send({ error: { code: 'UPDATE_FAILED', message: updateError.message } })
    }

    return reply.send({ success: true, daily_time_limit_minutes })
  })

  // ============================================================
  // GET /api/v1/parent/children/:childId/content-settings
  // Get content settings for a child
  // ============================================================
  app.get('/api/v1/parent/children/:childId/content-settings', {
    preHandler: async (request, reply) => {
      await authenticate(request, reply, app)
    }
  }, async (request: FastifyRequest, reply: FastifyReply) => {
    const { childId } = request.params as { childId: string }

    // Verify authorization
    const userId = (request as any).userId
    const { data: link, error: linkError } = await app.supabase
      .from('child_data.child_accounts')
      .select('parent_id, content_filter_level, scene_access')
      .eq('child_id', childId)
      .single()

    if (linkError || !link) {
      return reply.status(404).send({ error: { code: 'CHILD_NOT_FOUND', message: 'Child account not found' } })
    }

    if (link.parent_id !== userId) {
      return reply.status(403).send({ error: { code: 'FORBIDDEN', message: 'Not authorized to view this child\'s settings' } })
    }

    const sceneAccess = link.scene_access as Record<string, boolean> | null

    return reply.send({
      scenes: {
        spiritForest: sceneAccess?.spiritForest ?? true,
        spellLibrary: sceneAccess?.spellLibrary ?? true,
        rainbowGarden: sceneAccess?.rainbowGarden ?? true
      },
      filterLevel: link.content_filter_level || 'moderate'
    })
  })

  // ============================================================
  // PUT /api/v1/parent/children/:childId/content-settings
  // Update content settings for a child
  // ============================================================
  app.put('/api/v1/parent/children/:childId/content-settings', {
    preHandler: async (request, reply) => {
      await authenticate(request, reply, app)
    }
  }, async (request: FastifyRequest, reply: FastifyReply) => {
    const { childId } = request.params as { childId: string }
    const body = contentSettingsSchema.parse(request.body)
    const { scenes, filterLevel } = body

    // Verify authorization
    const userId = (request as any).userId
    const { data: link, error: linkError } = await app.supabase
      .from('child_data.child_accounts')
      .select('parent_id')
      .eq('child_id', childId)
      .single()

    if (linkError || !link) {
      return reply.status(404).send({ error: { code: 'CHILD_NOT_FOUND', message: 'Child account not found' } })
    }

    if (link.parent_id !== userId) {
      return reply.status(403).send({ error: { code: 'FORBIDDEN', message: 'Not authorized to modify this child\'s settings' } })
    }

    const updates: Record<string, unknown> = {}
    if (filterLevel) updates.content_filter_level = filterLevel
    if (scenes) updates.scene_access = scenes

    if (Object.keys(updates).length === 0) {
      return reply.status(400).send({ error: { code: 'NO_UPDATES', message: 'No settings provided to update' } })
    }

    const { error: updateError } = await app.supabase
      .from('child_data.child_accounts')
      .update(updates)
      .eq('child_id', childId)

    if (updateError) {
      return reply.status(500).send({ error: { code: 'UPDATE_FAILED', message: updateError.message } })
    }

    return reply.send({ success: true, ...updates })
  })

  // ============================================================
  // DELETE /api/v1/parent/children/:childId/data
  // Delete all data for a child (preserves user record)
  // ============================================================
  app.delete('/api/v1/parent/children/:childId/data', {
    preHandler: async (request, reply) => {
      await authenticate(request, reply, app)
    }
  }, async (request: FastifyRequest, reply: FastifyReply) => {
    const { childId } = request.params as { childId: string }

    // Verify authorization
    const userId = (request as any).userId
    const { data: link, error: linkError } = await app.supabase
      .from('child_data.child_accounts')
      .select('parent_id')
      .eq('child_id', childId)
      .single()

    if (linkError || !link) {
      return reply.status(404).send({ error: { code: 'CHILD_NOT_FOUND', message: 'Child account not found' } })
    }

    if (link.parent_id !== userId) {
      return reply.status(403).send({ error: { code: 'FORBIDDEN', message: 'Not authorized to delete this child\'s data' } })
    }

    // Delete all child-related data (vocabulary_entries is global, skip it)
    const deletions = [
      app.supabase.from('dialogue_turns').delete().eq('user_id', childId),
      app.supabase.from('game_sessions').delete().eq('user_id', childId),
      app.supabase.from('quest_progress').delete().eq('user_id', childId),
      app.supabase.from('player_rewards').delete().eq('user_id', childId),
      app.supabase.from('assessment_results').delete().eq('user_id', childId)
    ]

    const results = await Promise.all(deletions)
    const errors = results.filter(r => r.error)

    if (errors.length > 0) {
      return reply.status(500).send({
        error: {
          code: 'PARTIAL_DELETE_FAILED',
          message: errors.map(e => e!.error!.message).join('; ')
        }
      })
    }

    // Mark child user as inactive
    await app.supabase
      .from('users')
      .update({ is_active: false })
      .eq('user_id', childId)

    return reply.send({ success: true, message: 'All child data deleted and account deactivated' })
  })
}

/**
 * Convert CEFR level to a percentage progress value.
 * Levels: pre-A1, A1, A2, B1, B2, C1, C2
 */
function cefrProgressPercent(level: string): number {
  const levels: Record<string, number> = {
    'pre-A1': 5,
    'A1': 15,
    'A2': 30,
    'B1': 50,
    'B2': 70,
    'C1': 85,
    'C2': 100
  }
  return levels[level] ?? 5
}
