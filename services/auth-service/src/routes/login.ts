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

    // If user is a child, look up their parent_id from child_accounts
    let parentId = data.user!.id
    const { data: parentData, error: parentError } = await app.supabase
      .from('child_data.child_accounts')
      .select('parent_id')
      .eq('child_id', data.user.id)
      .maybeSingle()

    if (!parentError && parentData?.parent_id) {
      parentId = parentData.parent_id
    }

    return reply.send({
      token: data.session!.access_token,
      parent_id: parentId,
      user_id: data.user!.id,
      email: data.user!.email!,
      refresh_token: data.session!.refresh_token
    })
  })
}
