import { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify'
import { z } from 'zod'

const loginSchema = z.object({
  email: z.string().email(),
  password: z.string().min(1)
})

export async function registerLoginRoutes(app: FastifyInstance) {
  app.post('/api/v1/auth/login', async (request: FastifyRequest, reply: FastifyReply) => {
    const body = loginSchema.parse(request.body)
    const { email, password } = body

    const { data, error } = await app.supabase.auth.signInWithPassword({
      email,
      password
    })

    if (error) {
      return reply.status(401).send({ error: { code: 'LOGIN_FAILED', message: error.message } })
    }

    return reply.send({
      user_id: data.user!.id,
      email: data.user!.email!,
      access_token: data.session!.access_token,
      refresh_token: data.session!.refresh_token
    })
  })
}
