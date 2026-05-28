import WebSocket from 'ws'

/**
 * Manages WebSocket connections for quest event streaming.
 * Each user_id can have one active connection.
 */
export class QuestSessionManager {
  private connections = new Map<string, WebSocket>()

  /** Attach a WebSocket connection for a user */
  attach(userId: string, connection: WebSocket): void {
    // If user already has a connection, close the old one
    const existing = this.connections.get(userId)
    if (existing && existing.readyState === WebSocket.OPEN) {
      existing.close(1000, 'Replaced by new connection')
    }
    this.connections.set(userId, connection)
    console.log(`[QuestWS] User ${userId} connected (${this.connections.size} active)`)
  }

  /** Detach a WebSocket connection for a user */
  detach(userId: string): void {
    this.connections.delete(userId)
    console.log(`[QuestWS] User ${userId} disconnected (${this.connections.size} active)`)
  }

  /** Send a quest event to a specific user */
  sendToUser(userId: string, event: QuestEvent): boolean {
    const ws = this.connections.get(userId)
    if (!ws || ws.readyState !== WebSocket.OPEN) {
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
        this.connections.delete(userId)
      }
    }
  }
}

export type QuestEventType =
  | 'quest_completed'
  | 'badge_unlocked'
  | 'daily_quest_reset'
  | 'quest_status_changed'

export interface QuestEvent {
  type: QuestEventType
  payload: Record<string, unknown>
  timestamp: string
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
