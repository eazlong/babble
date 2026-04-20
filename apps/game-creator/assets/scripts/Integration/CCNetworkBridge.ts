/**
 * CCNetworkBridge - Wraps HttpClient and WebSocketClient, manages connection
 * lifecycle and emits coach_hint events for UI components to consume.
 */

import { _decorator, Component } from 'cc'
import { http } from '@linguaquest/game-client/network/HttpClient'
import { ws } from '@linguaquest/game-client/network/WebSocketClient'

const { ccclass, property } = _decorator

@ccclass('CCNetworkBridge')
export class CCNetworkBridge extends Component {
  private coachHintHandler: ((data: unknown) => void) | null = null

  start() {
    // Initialize HTTP client with auth token
    const userId = this.getStoredUserId()
    if (userId) {
      http.setAuthToken(userId)
    }

    // Connect WebSocket for real-time coach hints
    ws.connect().then(() => {
      console.log('[CCNetworkBridge] WebSocket connected')

      // Listen for coach_hint events
      this.coachHintHandler = (data: unknown) => {
        this.node.emit('coach_hint', data)
      }
      ws.on('coach_hint', this.coachHintHandler)
    }).catch((error) => {
      console.warn('[CCNetworkBridge] WebSocket connection failed:', error)
    })
  }

  onDisable() {
    // Clean up WebSocket listeners
    if (this.coachHintHandler) {
      ws.off('coach_hint', this.coachHintHandler)
    }
  }

  private getStoredUserId(): string | null {
    // In production, read from Supabase auth session
    try {
      return localStorage.getItem('user_id')
    } catch {
      return null
    }
  }
}
