interface SessionEntry {
  send(message: string): void
  lastActive: number
}

export class CoachSessionManager {
  private readonly sessions = new Map<string, SessionEntry>()

  attach(sessionId: string, socket: { send(message: string): void }) {
    this.sessions.set(sessionId, { send: socket.send.bind(socket), lastActive: Date.now() })
  }

  detach(sessionId: string) {
    this.sessions.delete(sessionId)
  }

  async push(sessionId: string, payload: Record<string, unknown>) {
    const entry = this.sessions.get(sessionId)
    if (!entry) {
      return
    }

    entry.lastActive = Date.now()
    entry.send(JSON.stringify(payload))
  }

  cleanupStaleSessions(maxAgeMs: number = 5 * 60 * 1000): number {
    const now = Date.now()
    let cleaned = 0
    for (const [sessionId, entry] of this.sessions) {
      if (now - entry.lastActive > maxAgeMs) {
        this.sessions.delete(sessionId)
        cleaned++
      }
    }
    return cleaned
  }
}
