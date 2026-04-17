export interface CoachHint {
  type: 'coach_hint'
  payload: {
    error: { type: string; correction: string; explanation: string }
    hint: string
  }
}

type ListenerCallback = (...args: unknown[]) => void

export class WebSocketClient {
  private ws: WebSocket | null = null
  private userId = ''
  private token = ''
  private listeners: Map<string, ListenerCallback[]> = new Map()

  connect(userId: string, token: string): void {
    this.userId = userId
    this.token = token
    this.ws = new WebSocket(
      `wss://realtime.linguaquest.com/realtime/v1/websocket?apikey=${token}`
    )

    this.ws.onmessage = (event) => {
      const data = JSON.parse(event.data as string)
      if (data.event === 'coach_hint') {
        this.notify('coach_hint', data.payload)
      }
    }

    this.ws.onclose = () => {
      setTimeout(() => this.connect(this.userId, this.token), 5000)
    }
  }

  on(event: string, callback: ListenerCallback): void {
    const list = this.listeners.get(event) ?? []
    list.push(callback)
    this.listeners.set(event, list)
  }

  private notify(event: string, payload: unknown): void {
    const callbacks = this.listeners.get(event) ?? []
    callbacks.forEach((cb) => cb(payload))
  }

  disconnect(): void {
    this.ws?.close()
    this.ws = null
  }
}
