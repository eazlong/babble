import { describe, expect, it, beforeEach } from 'vitest'
import { PromptBuilder, renderTemplate, buildContextFromInput } from '../services/prompt-builder.js'
import type { CoachInput } from '../types/coach-events.js'

describe('renderTemplate', () => {
  it('replaces simple variables', () => {
    const result = renderTemplate('Hello {{name}}!', { name: 'World' })
    expect(result).toBe('Hello World!')
  })

  it('replaces multiple variables', () => {
    const result = renderTemplate('{{a}} and {{b}}', { a: 'X', b: 'Y' })
    expect(result).toBe('X and Y')
  })

  it('replaces missing variables with empty string', () => {
    const result = renderTemplate('Hello {{name}}!', {})
    expect(result).toBe('Hello !')
  })

  it('handles {{#if var}} blocks when var is present', () => {
    const template = 'Before{{#if name}} NAME={{name}} {{/if}}After'
    const result = renderTemplate(template, { name: 'Alice' })
    expect(result).toBe('Before NAME=Alice After')
  })

  it('removes {{#if var}} blocks when var is missing', () => {
    const template = 'Before{{#if name}} NAME={{name}} {{/if}}After'
    const result = renderTemplate(template, {})
    expect(result).toBe('BeforeAfter')
  })

  it('removes {{#if var}} blocks when var is empty string', () => {
    const template = 'Before{{#if name}} NAME={{name}} {{/if}}After'
    const result = renderTemplate(template, { name: '' })
    expect(result).toBe('BeforeAfter')
  })

  it('handles nested content in if blocks', () => {
    const template = '{{#if x}}line1\nline2{{/if}}'
    const result = renderTemplate(template, { x: 'yes' })
    expect(result).toBe('line1\nline2')
  })
})

describe('buildContextFromInput', () => {
  it('extracts context from dialogue_turn', () => {
    const input = {
      event_type: 'dialogue_turn' as const,
      session_id: 's1',
      user_id: 'u1',
      npc_id: 'n1',
      player_text: 'I am go',
      npc_response: 'Good try!',
      language: 'en',
      timestamp: Date.now(),
      player_level: 'A2' as const,
      recent_turns: [
        { speaker: 'player' as const, text: 'hi' },
        { speaker: 'npc' as const, text: 'hello' },
      ],
    }
    const ctx = buildContextFromInput(input)
    expect(ctx.player_level).toBe('A2')
    expect(ctx.player_text).toBe('I am go')
    expect(ctx.npc_response).toBe('Good try!')
    expect(ctx.silence_seconds).toBe(0)
    expect(ctx.recent_turns).toContain('player: hi')
    expect(ctx.recent_turns).toContain('npc: hello')
  })

  it('extracts context from silence_timeout', () => {
    const input = {
      event_type: 'silence_timeout' as const,
      session_id: 's1',
      user_id: 'u1',
      npc_id: 'n1',
      silence_ms: 20000,
      timestamp: Date.now(),
      player_level: 'A1' as const,
      recent_turns: [],
    }
    const ctx = buildContextFromInput(input)
    expect(ctx.silence_seconds).toBe(20)
    expect(ctx.player_text).toBe('')
  })

  it('extracts context from wake_request', () => {
    const input = {
      event_type: 'wake_request' as const,
      session_id: 's1',
      user_id: 'u1',
      npc_id: 'n1',
      player_text: 'help me',
      timestamp: Date.now(),
      player_level: 'B1' as const,
      recent_turns: [],
    }
    const ctx = buildContextFromInput(input)
    expect(ctx.player_text).toBe('help me')
    expect(ctx.player_level).toBe('B1')
  })

  it('defaults player_level to A1 when missing', () => {
    const input = {
      event_type: 'wake_request' as const,
      session_id: 's1',
      user_id: 'u1',
      npc_id: 'n1',
      player_text: 'help',
      timestamp: Date.now(),
    } as CoachInput
    const ctx = buildContextFromInput(input)
    expect(ctx.player_level).toBe('A1')
  })
})

describe('PromptBuilder', () => {
  let builder: PromptBuilder

  beforeEach(() => {
    builder = new PromptBuilder()
  })

  it('builds prompt bundle for error trigger', async () => {
    const input: CoachInput = {
      event_type: 'dialogue_turn',
      session_id: 's1',
      user_id: 'u1',
      npc_id: 'n1',
      player_text: 'I am go to school',
      npc_response: 'Almost right!',
      language: 'en',
      timestamp: Date.now(),
      player_level: 'A1',
      recent_turns: [],
    }

    const bundle = await builder.build('error', input)

    expect(bundle.system).toContain('小飞猫')
    expect(bundle.system).toContain('A1 等级')
    expect(bundle.user).toContain('I am go to school')
    expect(bundle.user).toContain('Almost right!')
    expect(bundle.user).toContain('A1')
  })

  it('builds prompt bundle for silence trigger', async () => {
    const input: CoachInput = {
      event_type: 'silence_timeout',
      session_id: 's1',
      user_id: 'u1',
      npc_id: 'n1',
      silence_ms: 15000,
      timestamp: Date.now(),
      player_level: 'B2',
      recent_turns: [],
    }

    const bundle = await builder.build('silence', input)

    expect(bundle.system).toContain('小飞猫')
    expect(bundle.user).toContain('15')
    expect(bundle.user).toContain('B2')
  })

  it('builds prompt bundle for wake trigger', async () => {
    const input: CoachInput = {
      event_type: 'wake_request',
      session_id: 's1',
      user_id: 'u1',
      npc_id: 'n1',
      player_text: 'help me please',
      timestamp: Date.now(),
      player_level: 'A2',
      recent_turns: [],
    }

    const bundle = await builder.build('wake', input)

    expect(bundle.system).toContain('小飞猫')
    expect(bundle.user).toContain('help me please')
    expect(bundle.user).toContain('A2')
  })

  it('includes recent_turns in rendered template', async () => {
    const input: CoachInput = {
      event_type: 'dialogue_turn',
      session_id: 's1',
      user_id: 'u1',
      npc_id: 'n1',
      player_text: 'I like cats',
      npc_response: 'Great!',
      language: 'en',
      timestamp: Date.now(),
      player_level: 'A1',
      recent_turns: [
        { speaker: 'player', text: 'hi' },
        { speaker: 'npc', text: 'hello there' },
      ],
    }

    const bundle = await builder.build('error', input)

    expect(bundle.user).toContain('player: hi')
    expect(bundle.user).toContain('npc: hello there')
  })

  it('omits recent_turns section when empty', async () => {
    const input: CoachInput = {
      event_type: 'dialogue_turn',
      session_id: 's1',
      user_id: 'u1',
      npc_id: 'n1',
      player_text: 'hello',
      npc_response: 'hi',
      language: 'en',
      timestamp: Date.now(),
      player_level: 'A1',
      recent_turns: [],
    }

    const bundle = await builder.build('error', input)

    // The conditional block should not render "最近对话:" when recent_turns is empty
    expect(bundle.user).not.toContain('最近对话')
  })
})
