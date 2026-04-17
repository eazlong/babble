import type { AudioConfig } from './types'

export class AudioManager {
  private audioContext: AudioContext | null = null
  private stream: MediaStream | null = null
  private source: MediaStreamAudioSourceNode | null = null

  async startCapture(config?: Partial<AudioConfig>): Promise<MediaStream> {
    const cfg: AudioConfig = {
      sampleRate: 16000,
      echoCancellation: true,
      noiseSuppression: true,
      autoGainControl: true,
      ...config
    }

    this.audioContext = new AudioContext({ sampleRate: cfg.sampleRate })
    this.stream = await navigator.mediaDevices.getUserMedia({
      audio: {
        echoCancellation: cfg.echoCancellation,
        noiseSuppression: cfg.noiseSuppression,
        autoGainControl: cfg.autoGainControl,
        sampleRate: cfg.sampleRate
      }
    })
    this.source = this.audioContext.createMediaStreamSource(this.stream)
    return this.stream
  }

  stopCapture(): void {
    this.stream?.getTracks().forEach((track) => track.stop())
    this.audioContext?.close()
    this.stream = null
    this.source = null
  }

  async playAudio(url: string): Promise<void> {
    if (!this.audioContext) return
    const audioBuffer = await this.loadAudio(url)
    const source = this.audioContext.createBufferSource()
    source.buffer = audioBuffer
    source.connect(this.audioContext.destination)
    source.start()
  }

  private async loadAudio(url: string): Promise<AudioBuffer> {
    const response = await fetch(url)
    const arrayBuffer = await response.arrayBuffer()
    return this.audioContext!.decodeAudioData(arrayBuffer)
  }

  getAudioNode(): MediaStreamAudioSourceNode | null {
    return this.source
  }
}
