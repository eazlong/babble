export class CoachPublisher {
  constructor(private readonly redis: { xadd(stream: string, id: string, ...pairs: string[]): Promise<string> }) {}

  async publishDialogueTurn(payload: {
    session_id: string
    user_id: string
    npc_id: string
    player_text: string
    npc_response: string
    language: string
    timestamp: number
  }) {
    await this.redis.xadd(
      'coach.input',
      '*',
      'event_type', 'dialogue_turn',
      'session_id', payload.session_id,
      'user_id', payload.user_id,
      'npc_id', payload.npc_id,
      'player_text', payload.player_text,
      'npc_response', payload.npc_response,
      'language', payload.language,
      'timestamp', String(payload.timestamp),
    )
  }
}
