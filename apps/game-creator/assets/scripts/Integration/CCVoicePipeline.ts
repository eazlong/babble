/**
 * CCVoicePipeline - Wraps the game-client VoicePipeline, connects to
 * CocosCreator's audio system for microphone capture and playback.
 */

import { _decorator, Component } from 'cc'
import { VoicePipeline } from '../game-client/audio/VoicePipeline'

const { ccclass, property } = _decorator

@ccclass('CCVoicePipeline')
export class CCVoicePipeline extends Component {
  private pipeline: VoicePipeline

  constructor() {
    super()
    this.pipeline = new VoicePipeline()
  }

  start() {
    // Set up event listeners
    this.pipeline.on('transcription', (text: string) => {
      this.node.emit('player_speech', text)
    })

    this.pipeline.on('npc_response', (data: { text: string; audio_url: string }) => {
      this.node.emit('npc_speech', data)
    })

    this.pipeline.on('error', (error: Error) => {
      console.error('[CCVoicePipeline] Pipeline error:', error)
    })
  }

  /**
   * Start listening for player speech in the context of a specific NPC dialogue.
   */
  async startListening(npcId: string, sessionId: string): Promise<void> {
    this.pipeline.setContext({ npcId, sessionId })
    await this.pipeline.startListening()
  }

  /**
   * Stop listening for player speech.
   */
  stopListening(): void {
    this.pipeline.stopListening()
  }

  /**
   * Play NPC response audio from TTS.
   */
  playResponse(audioUrl: string): void {
    this.pipeline.playAudio(audioUrl)
  }
}
