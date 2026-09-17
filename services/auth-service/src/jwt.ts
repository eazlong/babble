import jwt from 'jsonwebtoken'

export const JWT_SECRET = process.env.JWT_SECRET || 'dev-secret-change-me'

export const TOKEN_EXPIRES_IN = process.env.JWT_EXPIRES_IN || '7d'

export interface TokenPayload {
  /** user_id */
  sub: string
  email?: string
  account_type?: string
}

/**
 * Sign a self-contained JWT. `sub` carries the user_id (Supabase used the same
 * convention), so the auth middleware can read it back without a DB call.
 */
export function signToken(
  userId: string,
  email?: string,
  accountType?: string
): string {
  return jwt.sign(
    { email, account_type: accountType },
    JWT_SECRET,
    { subject: userId, expiresIn: TOKEN_EXPIRES_IN as jwt.SignOptions['expiresIn'] }
  )
}

/**
 * Verify a JWT and return its payload, or null if invalid/expired.
 */
export function verifyToken(token: string): TokenPayload | null {
  try {
    const decoded = jwt.verify(token, JWT_SECRET)
    if (typeof decoded === 'string') return null
    return {
      sub: decoded.sub as string,
      email: decoded.email as string | undefined,
      account_type: decoded.account_type as string | undefined
    }
  } catch {
    return null
  }
}
