interface SessionEntry {
  send(message: string): void
  lastActive: number
  sessionId: string
  interventionHistory: Record<string, unknown>[]
}

export class CoachSessionManager {
  private readonly sessions = new Map<string, SessionEntry>()
  private readonly sessionStates = new Map<string, CoachSessionState>()

  attach(sessionId: string, socket: { send(message: string): void }) {
    // Check for existing session state to restore
    const existingState = this.sessionStates.get(sessionId)

    const entry: SessionEntry = {
      send: socket.send.bind(socket),
      lastActive: Date.now(),
      sessionId,
      interventionHistory: existingState?.interventionHistory || [],
    }

    this.sessions.set(sessionId, entry)

    // If there was previous session state, send recovery notification
    if (existingState) {
      this.sendSessionRestored(sessionId, existingState)
    }
  }

  detach(sessionId: string) {
    // Preserve session state before detaching
    this.preserveSessionState(sessionId)
    this.sessions.delete(sessionId)
  }

  async push(sessionId: string, payload: Record<string, unknown>) {
    const entry = this.sessions.get(sessionId)
    if (!entry) {
      return
    }

    entry.lastActive = Date.now()
    // Cache intervention in history
    entry.interventionHistory.push(payload)
    // Keep only last 20 interventions to avoid memory bloat
    if (entry.interventionHistory.length > 20) {
      entry.interventionHistory = entry.interventionHistory.slice(-20)
    }
    entry.send(JSON.stringify(payload))
  }

  cleanupStaleSessions(maxAgeMs: number = 5 * 60 * 1000): number {
    const now = Date.now()
    let cleaned = 0
    for (const [sessionId, entry] of this.sessions) {
      if (now - entry.lastActive > maxAgeMs) {
        this.preserveSessionState(sessionId)
        this.sessions.delete(sessionId)
        cleaned++
      }
    }
    return cleaned
  }

  /** Preserve session state for potential recovery */
  private preserveSessionState(sessionId: string): void {
    const entry = this.sessions.get(sessionId)
    if (!entry) return

    const state: CoachSessionState = {
      sessionId,
      lastActive: entry.lastActive,
      interventionHistory: entry.interventionHistory,
    }
    this.sessionStates.set(sessionId, state)
  }

  /** Send session restoration notification */
  private sendSessionRestored(sessionId: string, state: CoachSessionState): void {
    const entry = this.sessions.get(sessionId)
    if (!entry) return

    const restorePayload = {
      type: 'session_restored',
      session_id: sessionId,
      last_interventions: state.interventionHistory.slice(-5), // Last 5 interventions
      last_active: state.lastActive,
    }
    entry.send(JSON.stringify(restorePayload))
  }

  /** Get session state */
  getSessionState(sessionId: string): CoachSessionState | undefined {
    return this.sessionStates.get(sessionId)
  }

  /** Clean up old session states */
  cleanupSessionStates(maxAgeMs: number = 30 * 60 * 1000): number {
    const now = Date.now()
    let cleaned = 0
    for (const [sessionId, state] of this.sessionStates) {
      if (now - state.lastActive > maxAgeMs && !this.sessions.has(sessionId)) {
        this.sessionStates.delete(sessionId)
        cleaned++
      }
    }
    return cleaned
  }
}

export interface CoachSessionState {
  sessionId: string
  lastActive: number
  interventionHistory: Record<string, unknown>[]
}
