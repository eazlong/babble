import { test, expect } from 'vitest'
import { PromptManager, NPCProfile } from '../services/prompt-manager'
import { NPCEngine, DialogueRequest } from '../services/npc-engine'

test('buildNPCSystemPrompt generates correct prompt', () => {
  const npc: NPCProfile = {
    name: '集市商人老王',
    name_cn: '老王',
    role: 'merchant',
    cefr_level: 'A1',
    personality: '热情好客'
  }

  const prompt = PromptManager.buildNPCSystemPrompt(npc, 'A1')
  expect(prompt).toContain('集市商人老王')
  expect(prompt).toContain('老王')
  expect(prompt).toContain('A1')
})

test('buildDialogueContext formats history correctly', () => {
  const history = [
    { speaker: 'Player', text: 'Hello' },
    { speaker: 'NPC', text: 'Hi there!' }
  ]

  const context = PromptManager.buildDialogueContext(history)
  expect(context).toBe('Player: Hello\nNPC: Hi there!')
})

test('buildDialogueContext returns empty for no history', () => {
  expect(PromptManager.buildDialogueContext([])).toBe('')
})

test('processDialogue returns NPC response with LXP', async () => {
  const engine = new NPCEngine()
  const npc: NPCProfile = {
    name: 'Test NPC',
    role: 'merchant',
    cefr_level: 'A1',
    personality: 'kind',
    teaches: ['greetings']
  }

  const request: DialogueRequest = {
    user_id: 'user-1',
    npc_id: 'npc-1',
    player_input: 'Hello, how much is this?',
    session_id: 'session-1',
    language: 'en',
    cefr_level: 'A1'
  }

  const result = await engine.processDialogue(request, npc, [])
  expect(result.npc_text).toBeTruthy()
  expect(result.lxp_earned).toBeGreaterThan(0)
  expect(result.flagged).toBe(false)
})
