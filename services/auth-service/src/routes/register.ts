import { randomUUID } from 'node:crypto'
import { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify'
import { z } from 'zod'
import bcrypt from 'bcryptjs'
import { signToken } from '../jwt.js'

const registerSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
  display_name: z.string().min(1).max(50),
  preferred_language: z.string().default('en'),
  target_language: z.string().default('en'),
  child_name: z.string().min(1).max(50).optional()
})

/** pg error code for UNIQUE constraint violation. */
function isUniqueViolation(err: unknown): boolean {
  return typeof err === 'object' && err !== null && (err as { code?: string }).code === '23505'
}

export async function registerRoutes(app: FastifyInstance) {
  app.post('/api/v1/auth/register', async (request: FastifyRequest, reply: FastifyReply) => {
    const parsed = registerSchema.safeParse(request.body)
    if (!parsed.success) {
      const issue = parsed.error.issues[0]
      const field = issue?.path.join('.') || 'body'
      const reason = issue?.message || 'Invalid request'
      return reply
        .status(400)
        .send({ error: { code: 'REGISTER_VALIDATION_FAILED', message: `${field}: ${reason}` } })
    }

    const { email, password, display_name, preferred_language, target_language, child_name } =
      parsed.data

    const parentId = randomUUID()
    const passwordHash = await bcrypt.hash(password, 10)

    try {
      await app.db.query(
        `INSERT INTO users
           (user_id, email, password_hash, display_name, account_type, age_group,
            preferred_language, target_language, subscription_status)
         VALUES ($1, $2, $3, $4, 'parent', 'adult', $5, $6, 'free')`,
        [parentId, email, passwordHash, display_name, preferred_language, target_language]
      )
    } catch (err) {
      if (isUniqueViolation(err)) {
        return reply.status(409).send({
          error: { code: 'EMAIL_ALREADY_REGISTERED', message: 'An account with this email already exists' }
        })
      }
      return reply.status(500).send({
        error: { code: 'USER_CREATE_FAILED', message: 'Failed to create account', retryable: true }
      })
    }

    let childId: string | null = null

    if (child_name) {
      childId = randomUUID()
      const childEmail = `child_${childId}@linguaquest.local`
      const childHash = await bcrypt.hash('child_default_' + childId, 10)
      try {
        await app.db.query(
          `INSERT INTO users
             (user_id, email, password_hash, display_name, account_type, age_group,
              preferred_language, target_language, subscription_status)
           VALUES ($1, $2, $3, $4, 'child', 'child', $5, $6, 'free')`,
          [childId, childEmail, childHash, child_name, preferred_language, target_language]
        )
        await app.db.query(
          `INSERT INTO child_data.child_accounts
             (parent_id, child_id, daily_time_limit_minutes, content_filter_level)
           VALUES ($1, $2, 30, 'moderate')`,
          [parentId, childId]
        )
      } catch {
        return reply.status(500).send({
          error: { code: 'CHILD_CREATE_FAILED', message: 'Failed to create child account', retryable: true }
        })
      }
    }

    const token = signToken(parentId, email, 'parent')

    return reply.status(201).send({
      token,
      user_id: parentId,
      parent_id: parentId,
      email,
      display_name,
      child_id: childId
    })
  })
}
