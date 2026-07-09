import WebSocket from 'ws'

/**
 * Manages WebSocket connections for quest event streaming.
 * Each user_id can have one active connection.
 * Supports session state persistence and recovery.
 */
export class QuestSessionManager {
  private connections = new Map<string, WebSocket>()
  private sessionStates = new Map<string, QuestSessionState>()

  /** Attach a WebSocket connection for a user */
  attach(userId: string, connection: WebSocket): void {
    // Check for existing session state to restore
    const existingState = this.sessionStates.get(userId)
    
    // If user already has a connection, close the old one
    const existing = this.connections.get(userId)
    if (existing && existing.readyState === WebSocket.OPEN) {
      existing.close(1000, 'Replaced by new connection')
    }
    this.connections.set(userId, connection)
    
    console.log(`[QuestWS] User ${userId} connected (${this.connections.size} active)`)
    
    // If there was previous session state, send recovery notification
    if (existingState) {
      this.sendSessionRestored(userId, existingState)
    }
  }

  /** Detach a WebSocket connection for a user */
  detach(userId: string): void {
    // Preserve session state before detaching
    this.preserveSessionState(userId)
    this.connections.delete(userId)
    console.log(`[QuestWS] User ${userId} disconnected (${this.connections.size} active)`)
  }

  /** Send a quest event to a specific user */
  sendToUser(userId: string, event: QuestEvent): boolean {
    const ws = this.connections.get(userId)
    if (!ws || ws.readyState !== WebSocket.OPEN) {
      // Queue event for delivery when user reconnects
      this.queueEventForUser(userId, event)
      return false
    }
    ws.send(JSON.stringify(event))
    return true
  }

  /** Get count of active connections */
  getConnectionCount(): number {
    return this.connections.size
  }

  /** Clean up stale/closed connections */
  cleanup(): void {
    for (const [userId, ws] of this.connections) {
      if (ws.readyState !== WebSocket.OPEN) {
        this.preserveSessionState(userId)
        this.connections.delete(userId)
      }
    }
  }

  /** Preserve session state for potential recovery */
  private preserveSessionState(userId: string): void {
    const existingState = this.sessionStates.get(userId)
    const state: QuestSessionState = {
      userId,
      lastActive: Date.now(),
      eventHistory: existingState?.eventHistory || [],
      pendingEvents: existingState?.pendingEvents || [],
    }
    this.sessionStates.set(userId, state)
    console.log(`[QuestWS] Session state preserved for ${userId}`)
  }

  /** Queue an event for delivery when user reconnects */
  private queueEventForUser(userId: string, event: QuestEvent): void {
    let state = this.sessionStates.get(userId)
    if (!state) {
      state = {
        userId,
        lastActive: Date.now(),
        eventHistory: [],
        pendingEvents: [],
      }
      this.sessionStates.set(userId, state)
    }
    state.pendingEvents.push(event)
    console.log(`[QuestWS] Event queued for ${userId}: ${event.type}`)
  }

  /** Send session restoration notification with pending events */
  private sendSessionRestored(userId: string, state: QuestSessionState): void {
    const ws = this.connections.get(userId)
    if (!ws || ws.readyState !== WebSocket.OPEN) return

    // Send pending events first
    for (const event of state.pendingEvents) {
      ws.send(JSON.stringify(event))
    }

    // Send session restored notification
    const restoreEvent: QuestEvent = {
      type: 'session_restored',
      payload: {
        userId,
        pendingEventsCount: state.pendingEvents.length,
        lastActive: state.lastActive,
      },
      timestamp: new Date().toISOString(),
    }
    ws.send(JSON.stringify(restoreEvent))

    // Clear pending events after sending
    state.pendingEvents = []
    console.log(`[QuestWS] Session restored for ${userId}, ${restoreEvent.payload.pendingEventsCount} pending events sent`)
  }

  /** Get session state for a user */
  getSessionState(userId: string): QuestSessionState | undefined {
    return this.sessionStates.get(userId)
  }

  /** Clean up old session states */
  cleanupSessionStates(maxAgeMs: number = 30 * 60 * 1000): void {
    const now = Date.now()
    for (const [userId, state] of this.sessionStates) {
      if (now - state.lastActive > maxAgeMs && !this.connections.has(userId)) {
        this.sessionStates.delete(userId)
        console.log(`[QuestWS] Old session state cleaned up for ${userId}`)
      }
    }
  }
}

export type QuestEventType =
  | 'quest_completed'
  | 'badge_unlocked'
  | 'daily_quest_reset'
  | 'quest_status_changed'
  | 'session_restored'

export interface QuestEvent {
  type: QuestEventType
  payload: Record<string, unknown>
  timestamp: string
}

export interface QuestSessionState {
  userId: string
  lastActive: number
  eventHistory: QuestEvent[]
  pendingEvents: QuestEvent[]
}

/** Helper to create quest events */
export function createQuestEvent(
  type: QuestEventType,
  payload: Record<string, unknown>
): QuestEvent {
  return {
    type,
    payload,
    timestamp: new Date().toISOString(),
  }
}
