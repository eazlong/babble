import { AudioManager } from './AudioManager'
import { VADDetector } from './VADDetector'
import { http } from '../network/HttpClient'

export interface TurnResult {
  asr_text: string
  npc_text: string
  audio_url: string
  lxp_earned: number
}

export class VoicePipeline {
  private audioManager: AudioManager
  private vadDetector: VADDetector
  private onTurnComplete: ((result: TurnResult) => void) | null = null
  private onError: ((error: Error) => void) | null = null
  private currentNpcId = ''
  private currentSessionId = ''
  private currentLanguage = 'en'

  constructor() {
    this.audioManager = new AudioManager()
    this.vadDetector = new VADDetector()

    this.vadDetector.onSpeechEnd = async (audioChunk) => {
      await this.processSpeech(audioChunk)
    }
  }

  setContext(npcId: string, sessionId: string, language: string) {
    this.currentNpcId = npcId
    this.currentSessionId = sessionId
    this.currentLanguage = language
  }

  onTurnComplete(callback: (result: TurnResult) => void): void {
    this.onTurnComplete = callback
  }

  onError(callback: (error: Error) => void): void {
    this.onError = callback
  }

  async start(): Promise<void> {
    await this.audioManager.startCapture()
    const node = this.audioManager.getAudioNode()
    if (node) {
      this.vadDetector.start(node.context.createAnalyser())
    }
  }

  stop(): void {
    this.vadDetector.stop()
    this.audioManager.stopCapture()
  }

  private async processSpeech(audioChunk: Float32Array): Promise<void> {
    try {
      const wavBlob = this.audioToWav(audioChunk)
      const formData = new FormData()
      formData.append('audio', wavBlob, 'speech.wav')
      formData.append('language', this.currentLanguage)

      const { data: asrResult, error } = await http.post<{
        text: string
        confidence: number
        language: string
      }>('/voice/asr', formData)

      if (error ?? !asrResult) {
        this.onError?.(new Error(error?.message ?? 'ASR failed'))
        return
      }

      const { data: dialogueResult, error: dialogueError } = await http.post<{
        npc_text: string
        lxp_earned: number
      }>('/dialogue', {
        npc_id: this.currentNpcId,
        player_input: asrResult.text,
        session_id: this.currentSessionId,
        language: this.currentLanguage
      })

      if (dialogueError ?? !dialogueResult) {
        this.onError?.(new Error(dialogueError?.message ?? 'Dialogue failed'))
        return
      }

      const { data: ttsResult } = await http.post<{ audio_url: string }>('/voice/tts', {
        text: dialogueResult.npc_text,
        voice_id: 'merchant'
      })

      if (ttsResult?.audio_url) {
        await this.audioManager.playAudio(ttsResult.audio_url)
      }

      this.onTurnComplete?.({
        asr_text: asrResult.text,
        npc_text: dialogueResult.npc_text,
        audio_url: ttsResult?.audio_url ?? '',
        lxp_earned: dialogueResult.lxp_earned ?? 0
      })
    } catch (err) {
      this.onError?.(err as Error)
    }
  }

  private audioToWav(samples: Float32Array): Blob {
    const numChannels = 1
    const sampleRate = 16000
    const bitsPerSample = 16
    const byteRate = sampleRate * numChannels * (bitsPerSample / 8)
    const blockAlign = numChannels * (bitsPerSample / 8)
    const dataSize = samples.length * (bitsPerSample / 8)
    const buffer = new ArrayBuffer(44 + dataSize)
    const view = new DataView(buffer)

    const writeString = (offset: number, str: string) => {
      for (let i = 0; i < str.length; i++) {
        view.setUint8(offset + i, str.charCodeAt(i))
      }
    }

    writeString(0, 'RIFF')
    view.setUint32(4, 36 + dataSize, true)
    writeString(8, 'WAVE')
    writeString(12, 'fmt ')
    view.setUint32(16, 16, true)
    view.setUint16(20, 1, true)
    view.setUint16(22, numChannels, true)
    view.setUint32(24, sampleRate, true)
    view.setUint32(28, byteRate, true)
    view.setUint16(32, blockAlign, true)
    view.setUint16(34, bitsPerSample, true)
    writeString(36, 'data')
    view.setUint32(40, dataSize, true)

    for (let i = 0; i < samples.length; i++) {
      const s = Math.max(-1, Math.min(1, samples[i]))
      view.setInt16(44 + i * 2, s < 0 ? s * 0x8000 : s * 0x7fff, true)
    }

    return new Blob([buffer], { type: 'audio/wav' })
  }
}
