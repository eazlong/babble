import { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify'
import { z } from 'zod'
import bcrypt from 'bcryptjs'
import { signToken } from '../jwt.js'

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1)
})

export async function registerLoginRoutes(app: FastifyInstance) {
  app.post('/api/v1/auth/login', async (request: FastifyRequest, reply: FastifyReply) => {
    const parsed = loginSchema.safeParse(request.body)
    if (!parsed.success) {
      return reply
        .status(400)
        .send({ error: { code: 'LOGIN_VALIDATION_FAILED', message: 'Invalid email or password' } })
    }
    const { email, password } = parsed.data

    const rows = await app.db.query<{
      user_id: string
      email: string
      password_hash: string
      account_type: string
      display_name: string
    }>(
      `SELECT user_id, email, password_hash, account_type, display_name
         FROM users
        WHERE email = $1 AND is_active = TRUE`,
      [email]
    )

    if (rows.length === 0) {
      return reply
        .status(401)
        .send({ error: { code: 'LOGIN_FAILED', message: 'Invalid email or password' } })
    }

    const user = rows[0]
    const ok = await bcrypt.compare(password, user.password_hash)
    if (!ok) {
      return reply.status(401).send({
        error: { code: 'LOGIN_FAILED', message: 'Invalid email or password' }
      })
    }

    // If a child logs in, surface their parent_id (same behavior as before).
    let parentId = user.user_id
    if (user.account_type === 'child') {
      const accountRows = await app.db.query<{ parent_id: string }>(
        `SELECT parent_id FROM child_data.child_accounts WHERE child_id = $1`,
        [user.user_id]
      )
      if (accountRows.length > 0) parentId = accountRows[0].parent_id
    }

    const token = signToken(user.user_id, user.email, user.account_type)

    return reply.send({
      token,
      parent_id: parentId,
      user_id: user.user_id,
      email: user.email,
      refresh_token: null
    })
  })
}
