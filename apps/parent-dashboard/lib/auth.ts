const AUTH_TOKEN_KEY = 'linguaquest_auth_token'
const PARENT_ID_KEY = 'linguaquest_parent_id'

export function getAuthToken(): string | null {
  if (typeof window === 'undefined') return null
  return localStorage.getItem(AUTH_TOKEN_KEY)
}

export function setAuthToken(token: string): void {
  if (typeof window === 'undefined') return
  localStorage.setItem(AUTH_TOKEN_KEY, token)
}

export function getParentId(): string | null {
  if (typeof window === 'undefined') return null
  return localStorage.getItem(PARENT_ID_KEY)
}

export function setParentId(parentId: string): void {
  if (typeof window === 'undefined') return
  localStorage.setItem(PARENT_ID_KEY, parentId)
}

export function clearAuth(): void {
  if (typeof window === 'undefined') return
  localStorage.removeItem(AUTH_TOKEN_KEY)
  localStorage.removeItem(PARENT_ID_KEY)
}

export function isAuthenticated(): boolean {
  return getAuthToken() !== null
}
