import { FastifyInstance, FastifyReply, FastifyRequest } from 'fastify'
import { z } from 'zod'

const registerSchema = z.object({
  email: z.string().email(),
  password: z.string().min(8),
  display_name: z.string().min(1).max(50),
  preferred_language: z.string().default('en'),
  target_language: z.string().default('en'),
  child_name: z.string().min(1).max(50).optional()
})

export async function registerRoutes(app: FastifyInstance) {
  app.post('/api/v1/auth/register', async (request: FastifyRequest, reply: FastifyReply) => {
    const body = registerSchema.parse(request.body)
    const { email, password, display_name, preferred_language, target_language, child_name } = body

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

    const parentId = data.user!.id

    // Create parent user record
    const { error: parentInsertError } = await app.supabase.from('users').insert({
      user_id: parentId,
      email,
      display_name,
      account_type: 'parent',
      age_group: 'adult',
      preferred_language,
      target_language,
      subscription_status: 'free'
    })

    if (parentInsertError) {
      return reply.status(500).send({ error: { code: 'USER_CREATE_FAILED', message: parentInsertError.message } })
    }

    let childId: string | null = null

    // If child_name provided, create child account and link
    if (child_name) {
      // Create child auth user
      const childEmail = `child_${parentId}@linguaquest.local`
      const { data: childAuthData, error: childAuthError } = await app.supabase.auth.signUp({
        email: childEmail,
        password: 'child_default_' + parentId,
        options: {
          data: {
            display_name: child_name,
            preferred_language,
            target_language
          }
        }
      })

      if (childAuthError) {
        return reply.status(500).send({ error: { code: 'CHILD_AUTH_CREATE_FAILED', message: childAuthError.message } })
      }

      childId = childAuthData.user!.id

      // Create child user record
      const { error: childInsertError } = await app.supabase.from('users').insert({
        user_id: childId,
        email: childEmail,
        display_name: child_name,
        account_type: 'child',
        age_group: 'child',
        preferred_language,
        target_language,
        subscription_status: 'free'
      })

      if (childInsertError) {
        return reply.status(500).send({ error: { code: 'CHILD_USER_CREATE_FAILED', message: childInsertError.message } })
      }

      // Create child_accounts linkage
      const { error: linkError } = await app.supabase.from('child_data.child_accounts').insert({
        parent_id: parentId,
        child_id: childId,
        daily_time_limit_minutes: 30,
        content_filter_level: 'moderate'
      })

      if (linkError) {
        return reply.status(500).send({ error: { code: 'CHILD_ACCOUNT_LINK_FAILED', message: linkError.message } })
      }
    }

    return reply.status(201).send({
      token: data.session?.access_token || null,
      user_id: parentId,
      parent_id: parentId,
      email: data.user!.email!,
      display_name,
      child_id: childId
    })
  })
}
