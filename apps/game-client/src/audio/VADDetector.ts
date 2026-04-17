export type VADState = 'silence' | 'speaking' | 'unknown'

export interface VADConfig {
  silenceThreshold: number
  speechStartDelay: number
  speechEndDelay: number
}

export class VADDetector {
  private state: VADState = 'unknown'
  private config: VADConfig = {
    silenceThreshold: 0.01,
    speechStartDelay: 100,
    speechEndDelay: 1500
  }

  private analyser: AnalyserNode | null = null
  private rafId: number | null = null
  private silenceStartTime: number | null = null

  onSpeechStart: (() => void) | null = null
  onSpeechEnd: ((audioChunk: Float32Array) => void) | null = null
  onSilence: ((durationMs: number) => void) | null = null

  start(analyser: AnalyserNode): void {
    this.analyser = analyser
    this.detect()
  }

  stop(): void {
    if (this.rafId) {
      cancelAnimationFrame(this.rafId)
      this.rafId = null
    }
  }

  private detect(): void {
    if (!this.analyser) return

    const data = new Float32Array(this.analyser.fftSize)
    this.analyser.getFloatTimeDomainData(data)

    const rms = Math.sqrt(data.reduce((sum, val) => sum + val * val, 0) / data.length)

    if (rms > this.config.silenceThreshold && this.state !== 'speaking') {
      this.state = 'speaking'
      this.silenceStartTime = null
      this.onSpeechStart?.()
    } else if (rms <= this.config.silenceThreshold && this.state === 'speaking') {
      if (!this.silenceStartTime) {
        this.silenceStartTime = Date.now()
      } else if (Date.now() - this.silenceStartTime >= this.config.speechEndDelay) {
        this.state = 'silence'
        this.onSpeechEnd?.(data)
      }
    } else if (this.state === 'silence' && rms <= this.config.silenceThreshold) {
      this.silenceStartTime ??= Date.now()
      const duration = Date.now() - this.silenceStartTime
      if (duration >= 5000) {
        this.onSilence?.(duration)
        this.silenceStartTime = Date.now()
      }
    } else {
      this.silenceStartTime = null
    }

    this.rafId = requestAnimationFrame(() => this.detect())
  }
}
