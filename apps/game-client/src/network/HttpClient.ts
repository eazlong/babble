
import type { ApiResponse } from './types'

const API_BASE = 'https://api.linguaquest.com/api/v1'

export class HttpClient {
  private token: string | null = null

  setAuthToken(token: string) {
    this.token = token
  }

  async post<T>(path: string, body: unknown): Promise<ApiResponse<T>> {
    const response = await fetch(`${API_BASE}${path}`, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        ...(this.token ? { Authorization: `Bearer ${this.token}` } : {})
      },
      body: JSON.stringify(body)
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

// Stub HttpClient - will be replaced with real implementation
export const http = {
  async get(_url: string) {
    return { data: null }
  },
  async post(_url: string, _body: unknown) {
    return { data: null }
  }
}