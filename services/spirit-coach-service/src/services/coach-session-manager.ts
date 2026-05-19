export class CoachSessionManager {
  private readonly sessions = new Map<string, { send(message: string): void }>()

  attach(sessionId: string, socket: { send(message: string): void }) {
    this.sessions.set(sessionId, socket)
  }

  detach(sessionId: string) {
    this.sessions.delete(sessionId)
  }

  async push(sessionId: string, payload: Record<string, unknown>) {
    const socket = this.sessions.get(sessionId)
    if (!socket) {
      return
    }

    socket.send(JSON.stringify(payload))
  }
}
