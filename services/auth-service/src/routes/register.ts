import { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify'
import { z } from 'zod'

const registerSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
  display_name: z.string().min(1).max(50),
  preferred_language: z.string().default('en'),
  target_language: z.string().default('en')
})

export async function registerRoutes(app: FastifyInstance) {
  app.post('/api/v1/auth/register', async (request: FastifyRequest, reply: FastifyReply) => {
    const body = registerSchema.parse(request.body)
    const { email, password, display_name, preferred_language, target_language } = body

    // Supabase Auth signup
    const { data, error } = await app.supabase.auth.signUp({
      email,
      password,
      options: {
        data: {
          display_name,
          preferred_language,
          target_language
        }
      }
    })

    if (error) {
      return reply.status(400).send({ error: { code: 'REGISTER_FAILED', message: error.message } })
    }

    // Create user record in public.users table
    const { error: insertError } = await app.supabase.from('users').insert({
      user_id: data.user!.id,
      email,
      display_name,
      account_type: 'standard',
      age_group: 'adult',
      preferred_language,
      target_language,
      subscription_status: 'free'
    })

    if (insertError) {
      return reply.status(500).send({ error: { code: 'USER_CREATE_FAILED', message: insertError.message } })
    }

    return reply.status(201).send({
      user_id: data.user!.id,
      email: data.user!.email!,
      display_name
    })
  })
}
