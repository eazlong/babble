import { FastifyRequest, FastifyReply, FastifyInstance } from 'fastify'
import { verifyToken } from '../jwt.js'

export interface AuthenticatedRequest extends FastifyRequest {
  userId: string
}

function bearerToken(authHeader: string | undefined): string | null {
  if (!authHeader) return null
  if (!authHeader.startsWith('Bearer ')) return null
  return authHeader.slice('Bearer '.length)
}

export async function authenticate(
  request: FastifyRequest,
  reply: FastifyReply,
  _app: FastifyInstance
) {
  const token = bearerToken(request.headers.authorization)
  if (!token) {
    return reply.status(401).send({ error: { code: 'UNAUTHORIZED', message: 'No token provided' } })
  }

  const payload = verifyToken(token)
  if (!payload?.sub) {
    return reply.status(401).send({ error: { code: 'INVALID_TOKEN', message: 'Invalid or expired token' } })
  }

  // Attach user ID to request (JWT `sub` = user_id).
  ;(request as AuthenticatedRequest).userId = payload.sub
}

/**
 * Validates token and returns userId, or null if invalid (already sent error reply).
 * Use this in route handlers where you need conditional auth logic.
 */
export async function authenticateWithReply(
  request: FastifyRequest,
  reply: FastifyReply,
  _app: FastifyInstance
): Promise<string | null> {
  const token = bearerToken(request.headers.authorization)
  if (!token) {
    reply.status(401).send({ error: { code: 'UNAUTHORIZED', message: 'No token provided' } })
    return null
  }

  const payload = verifyToken(token)
  if (!payload?.sub) {
    reply.status(401).send({ error: { code: 'INVALID_TOKEN', message: 'Invalid or expired token' } })
    return null
  }

  return payload.sub
}
