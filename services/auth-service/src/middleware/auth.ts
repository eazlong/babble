import { FastifyRequest, FastifyReply, FastifyInstance } from 'fastify'

export interface AuthenticatedRequest extends FastifyRequest {
  userId: string
}

export async function authenticate(
  request: FastifyRequest,
  reply: FastifyReply,
  app: FastifyInstance
) {
  const authHeader = request.headers.authorization
  if (!authHeader) {
    return reply.status(401).send({ error: { code: 'UNAUTHORIZED', message: 'No token provided' } })
  }

  const token = authHeader.replace('Bearer ', '')
  const { data, error } = await app.supabase.auth.getUser(token)

  if (error || !data.user) {
    return reply.status(401).send({ error: { code: 'INVALID_TOKEN', message: 'Invalid or expired token' } })
  }

  // Attach user ID to request
  ;(request as AuthenticatedRequest).userId = data.user.id
}
