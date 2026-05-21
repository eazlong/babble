
import type { ApiResponse } from './types'

const USE_LOCAL = typeof window !== 'undefined' && (window.location.hostname === 'localhost' || window.location.hostname === '127.0.0.1')

const API_BASE = USE_LOCAL
  ? 'http://localhost:8301'
  : 'https://api.linguaquest.com/api/v1'

const DIALOGUE_BASE = USE_LOCAL
  ? 'http://localhost:8302'
  : 'https://api.linguaquest.com/api/v1'

export class HttpClient {
  private token: string | null = null

  setAuthToken(token: string) {
    this.token = token
  }

  async post<T>(path: string, body: unknown, service?: 'voice' | 'dialogue'): Promise<ApiResponse<T>> {
    const base = service === 'dialogue' ? DIALOGUE_BASE : API_BASE
    const isFormData = body instanceof FormData
    const headers: Record<string, string> = {}
    if (!isFormData) {
      headers['Content-Type'] = 'application/json'
    }
    if (this.token) {
      headers['Authorization'] = `Bearer ${this.token}`
    }

    const response = await fetch(`${base}${path}`, {
      method: 'POST',
      headers,
      body: isFormData ? body : JSON.stringify(body)
    })

    const data = await response.json()

    if (!response.ok) {
      return { error: data.error ?? { code: 'UNKNOWN', message: 'Server error' } }
    }

    return { data }
  }

  async get<T>(path: string): Promise<ApiResponse<T>> {
    const response = await fetch(`${API_BASE}${path}`, {
      headers: {
        ...(this.token ? { Authorization: `Bearer ${this.token}` } : {})
      }
    })

    const data = await response.json()

    if (!response.ok) {
      return { error: data.error ?? { code: 'UNKNOWN', message: 'Server error' } }
    }

    return { data }
  }
}

export const http = new HttpClient()