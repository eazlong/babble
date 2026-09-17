import { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify'
import { z } from 'zod'
import { authenticate, authenticateWithReply } from '../middleware/auth.js'

// summary-service 地址（ADR-0008 诊断代理）。默认与 summary-service docker 端口一致。
// 已知坑：auth-service 本地也监听 8303，开发时需错开端口或改此 env。
const SUMMARY_SERVICE_URL = process.env.SUMMARY_SERVICE_URL || 'http://localhost:8303'

// Zod schemas for request validation
const timeLimitSchema = z.object({
  daily_time_limit_minutes: z.number().int().min(1).max(480)
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
      const { parentId } = request.params as { parentId: string }
      if (userId !== parentId) {
        reply.status(403).send({ error: { code: 'FORBIDDEN', message: 'Not authorized to access this parent account' } })
      }
    }
  }, async (request: FastifyRequest, reply: FastifyReply) => {
    const { parentId } = request.params as { parentId: string }

    // Get all children for this parent (join child_accounts + user profile)
    const children: Array<{
      child_id: string
      daily_time_limit_minutes: number
      content_filter_level: string
      display_name: string
      cefr_level: string
      age_group: string
    }> = await app.db.query(
      `SELECT ca.child_id, ca.daily_time_limit_minutes, ca.content_filter_level,
              u.display_name, u.cefr_level, u.age_group
         FROM child_data.child_accounts ca
         JOIN users u ON u.user_id = ca.child_id
        WHERE ca.parent_id = $1`,
      [parentId]
    )

    if (children.length === 0) {
      return reply.send({ children: [] })
    }

    const todayStart = new Date().toISOString().split('T')[0] // YYYY-MM-DD

    // Build dashboard data with aggregated stats for each child
    const dashboardChildren = await Promise.all(
      children.map(async (ca) => {
        const childId = ca.child_id

        // Today's game time
        const sessions = await app.db.query<{ start_time: string; end_time: string }>(
          `SELECT start_time, end_time FROM game_sessions
            WHERE user_id = $1 AND start_time >= $2`,
          [childId, todayStart]
        )

        let total_time_today = 0
        for (const s of sessions) {
          if (s.start_time && s.end_time) {
            total_time_today +=
              (new Date(s.end_time).getTime() - new Date(s.start_time).getTime()) / 60000
          }
        }

        // Vocabulary count (number of assessment results for this child)
        const vocab = await app.db.query<{ count: number }>(
          `SELECT count(*)::int AS count FROM assessment_results WHERE user_id = $1`,
          [childId]
        )

        // Quests completed
        const quests = await app.db.query<{ status: string }>(
          `SELECT status FROM quest_progress WHERE user_id = $1 AND status = 'completed'`,
          [childId]
        )

        return {
          child_id: childId,
          display_name: ca.display_name || 'Unknown',
          total_time_today: Math.round(total_time_today),
          daily_time_limit_minutes: ca.daily_time_limit_minutes,
          vocabulary_count: vocab[0]?.count || 0,
          cefr_level: ca.cefr_level || 'pre-A1',
          quests_completed: quests.length
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
    const childRows = await app.db.query<{ child_id: string }>(
      `SELECT child_id FROM child_data.child_accounts WHERE parent_id = $1`,
      [parentId]
    )
    const childIds = childRows.map((r) => r.child_id)

    if (childIds.length === 0) {
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

    const todayStart = new Date()
    todayStart.setHours(0, 0, 0, 0)
    const weekStart = new Date()
    weekStart.setDate(weekStart.getDate() - 7)
    const monthStart = new Date()
    monthStart.setDate(monthStart.getDate() - 30)

    const sumMinutes = (sessions: Array<{ start_time: string; end_time: string }>): number => {
      let sum = 0
      for (const s of sessions) {
        if (s.start_time && s.end_time) {
          sum += (new Date(s.end_time).getTime() - new Date(s.start_time).getTime()) / 60000
        }
      }
      return sum
    }

    const sessionsToday = await app.db.query<{ start_time: string; end_time: string }>(
      `SELECT start_time, end_time FROM game_sessions WHERE user_id = ANY($1) AND start_time >= $2`,
      [childIds, todayStart.toISOString()]
    )
    const total_time_today = sumMinutes(sessionsToday)

    const sessionsWeek = await app.db.query<{ start_time: string; end_time: string }>(
      `SELECT start_time, end_time FROM game_sessions WHERE user_id = ANY($1) AND start_time >= $2`,
      [childIds, weekStart.toISOString()]
    )
    const total_time_week = sumMinutes(sessionsWeek)

    const sessionsMonth = await app.db.query<{ start_time: string; end_time: string }>(
      `SELECT start_time, end_time FROM game_sessions WHERE user_id = ANY($1) AND start_time >= $2`,
      [childIds, monthStart.toISOString()]
    )
    const total_time_month = sumMinutes(sessionsMonth)

    // Vocabulary growth (assessment_results in last 30 days)
    const vocab = await app.db.query<{ count: number }>(
      `SELECT count(*)::int AS count FROM assessment_results
        WHERE user_id = ANY($1) AND assessed_at >= $2`,
      [childIds, monthStart.toISOString()]
    )
    const vocabulary_growth = vocab[0]?.count || 0

    // CEFR level from first child
    const users = await app.db.query<{ cefr_level: string }>(
      `SELECT cefr_level FROM users WHERE user_id = ANY($1) LIMIT 1`,
      [childIds]
    )
    const cefr_level = users[0]?.cefr_level || 'pre-A1'

    // Total quests completed
    const quests = await app.db.query<{ status: string }>(
      `SELECT status FROM quest_progress WHERE user_id = ANY($1) AND status = 'completed'`,
      [childIds]
    )

    return reply.send({
      total_time_today: Math.round(total_time_today),
      total_time_week: Math.round(total_time_week),
      total_time_month: Math.round(total_time_month),
      vocabulary_growth,
      cefr_level,
      cefr_progress: cefrProgressPercent(cefr_level),
      quests_completed: quests.length
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

    const userId = (request as any).userId
    const link = await app.db.query<{ parent_id: string }>(
      `SELECT parent_id FROM child_data.child_accounts WHERE child_id = $1`,
      [childId]
    )

    if (link.length === 0) {
      return reply.status(404).send({ error: { code: 'CHILD_NOT_FOUND', message: 'Child account not found' } })
    }

    if (link[0].parent_id !== userId) {
      return reply.status(403).send({ error: { code: 'FORBIDDEN', message: "Not authorized to modify this child's settings" } })
    }

    await app.db.query(
      `UPDATE child_data.child_accounts SET daily_time_limit_minutes = $2 WHERE child_id = $1`,
      [childId, daily_time_limit_minutes]
    )

    return reply.send({ success: true, daily_time_limit_minutes })
  })

  // ============================================================
  // GET /api/v1/parent/:parentId/diagnosis
  // 代理 summary-service 诊断层，裁剪为家长可见诊断（ADR-0008）。
  // 故障隔离：summary-service 不可用时降级，不 500。
  // ============================================================
  app.get('/api/v1/parent/:parentId/diagnosis', {
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

    // 单孩锁定（G1）：从 parent 解出唯一 child
    const childAccount = await app.db.query<{ child_id: string }>(
      `SELECT child_id FROM child_data.child_accounts WHERE parent_id = $1 LIMIT 1`,
      [parentId]
    )

    if (childAccount.length === 0) {
      return reply.send({ diagnosis: null, status: 'no_child' })
    }

    const childId = childAccount[0].child_id

    // 调 summary-service 诊断端点（无认证，靠网络边界 + 本代理监护校验保护）
    let summaryResp: any
    try {
      const res = await fetch(
        `${SUMMARY_SERVICE_URL}/api/v1/summary/report/diagnosis?child_id=${encodeURIComponent(childId)}`,
        { signal: AbortSignal.timeout(5000) }
      )
      if (!res.ok) {
        return reply.send({ diagnosis: null, status: 'generating' })
      }
      summaryResp = await res.json()
    } catch {
      // summary-service 不可用：降级，不 500（ADR-0008 故障隔离）
      return reply.send({ diagnosis: null, status: 'generating' })
    }

    // D1 裁剪：剥掉内部状态，只留家长可见字段
    return reply.send({
      diagnosis: {
        child_id: childId,
        summary: summaryResp.diagnosis,
        mastery_breakdown: trimBreakdown(summaryResp.mastery_breakdown),
        weak_items_ranked: trimItems(summaryResp.weak_items_ranked)
      },
      status: 'ok'
    })
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
    const link = await app.db.query<{ parent_id: string }>(
      `SELECT parent_id FROM child_data.child_accounts WHERE child_id = $1`,
      [childId]
    )

    if (link.length === 0) {
      return reply.status(404).send({ error: { code: 'CHILD_NOT_FOUND', message: 'Child account not found' } })
    }

    if (link[0].parent_id !== userId) {
      return reply.status(403).send({ error: { code: 'FORBIDDEN', message: "Not authorized to delete this child's data" } })
    }

    // Delete all child-related data (vocabulary_entries is global, skip it)
    const deletes = [
      `DELETE FROM dialogue_turns WHERE user_id = $1`,
      `DELETE FROM game_sessions WHERE user_id = $1`,
      `DELETE FROM quest_progress WHERE user_id = $1`,
      `DELETE FROM player_rewards WHERE user_id = $1`,
      `DELETE FROM assessment_results WHERE user_id = $1`
    ]

    const errors: unknown[] = []
    for (const sql of deletes) {
      try {
        await app.db.query(sql, [childId])
      } catch (e) {
        errors.push(e)
      }
    }

    if (errors.length > 0) {
      return reply.status(500).send({
        error: {
          code: 'PARTIAL_DELETE_FAILED',
          message: errors.map((e) => (e as { message?: string }).message || 'delete failed').join('; ')
        }
      })
    }

    // Mark child user as inactive
    await app.db.query(`UPDATE users SET is_active = FALSE WHERE user_id = $1`, [childId])

    return reply.send({ success: true, message: 'All child data deleted and account deactivated' })
  })
}

/**
 * D1 裁剪（ADR-0008 / CONTEXT 家长可见诊断）：
 * 剥掉保留强度数值、半衰期、上次掌握分（半衰期模型内部状态），
 * 只留知识项 ID / 类型 / 掌握档位 / 考查次数 / 上次考查时间。
 * weak_items_ranked 的顺序由 summary-service 已按 retention_strength 升序排好，代理只剥数值。
 */
function trimItem(state: any) {
  if (!state) return null
  return {
    knowledge_item_id: state.knowledge_item_id ?? '',
    item_type: state.item_type ?? '',
    mastery_band: state.mastery_band ?? '',
    assessment_count: state.assessment_count ?? 0,
    last_assessed_at: state.last_assessed_at ?? ''
  }
}

function trimItems(items: any[] | undefined): any[] {
  if (!Array.isArray(items)) return []
  return items.map(trimItem).filter(Boolean)
}

function trimBreakdown(breakdown: any) {
  if (!breakdown) return null
  return {
    mastered: trimItems(breakdown.mastered),
    partial: trimItems(breakdown.partial),
    unmastered: trimItems(breakdown.unmastered)
  }
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
