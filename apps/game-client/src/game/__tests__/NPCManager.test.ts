import { test, expect, vi, beforeEach, describe } from 'vitest'
import { NPCManager } from '../NPCManager'
import { http } from '../../network/HttpClient'

vi.mock('../../network/HttpClient', () => ({
  http: {
    get: vi.fn(),
    post: vi.fn(),
  },
}))

const mockNPCs = [
  {
    npc_id: 'npc-wizard',
    name: '魔法导师',
    dialogue_model: 'gpt-4o-mini',
    voice_id: 'wizard-voice',
    avatar_ref: 'wizard_avatar',
    cefr_level: 'A1',
    greeting: '你好！欢迎来到魔法森林',
    topics: ['colors', 'animals'],
    teaches: 'vocabulary',
    scene_id: 'forest-1',
    personality: 'wise and patient',
  },
  {
    npc_id: 'npc-merchant',
    name: '商店老板',
    dialogue_model: 'gpt-4o-mini',
    voice_id: 'merchant-voice',
    avatar_ref: 'merchant_avatar',
    cefr_level: 'A1',
    greeting: '来看看我的商品吧！',
    topics: ['numbers', 'food'],
    teaches: 'daily conversation',
    scene_id: 'forest-1',
    personality: 'friendly and enthusiastic',
  },
]

describe('NPCManager', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  test('loads NPCs from API', async () => {
    vi.mocked(http.get).mockResolvedValue({ data: mockNPCs })

    const manager = new NPCManager()
    const npcs = await manager.loadNPCs('forest-1')

    expect(npcs).toHaveLength(2)
    expect(npcs[0].teaches).toBe('vocabulary')
    expect(npcs[0].scene_id).toBe('forest-1')
    expect(npcs[0].personality).toBe('wise and patient')
  })

  test('throws on API error', async () => {
    vi.mocked(http.get).mockResolvedValue({ error: { code: 'NOT_FOUND', message: 'Scene not found' } })

    const manager = new NPCManager()
    await expect(manager.loadNPCs('invalid')).rejects.toThrow()
  })

  test('getNPC returns NPC by ID', async () => {
    vi.mocked(http.get).mockResolvedValue({ data: mockNPCs })

    const manager = new NPCManager()
    await manager.loadNPCs('forest-1')

    const npc = manager.getNPC('npc-wizard')
    expect(npc).not.toBeNull()
    expect(npc!.name).toBe('魔法导师')
  })

  test('getNPC returns null for unknown ID', async () => {
    vi.mocked(http.get).mockResolvedValue({ data: mockNPCs })

    const manager = new NPCManager()
    await manager.loadNPCs('forest-1')

    expect(manager.getNPC('unknown')).toBeNull()
  })

  test('setActiveNPC and getActiveNPC', async () => {
    vi.mocked(http.get).mockResolvedValue({ data: mockNPCs })

    const manager = new NPCManager()
    await manager.loadNPCs('forest-1')

    const active = manager.setActiveNPC('npc-merchant')
    expect(active).not.toBeNull()
    expect(manager.getActiveNPC()!.npc_id).toBe('npc-merchant')
  })

  test('setActiveNPC returns null for unknown ID', async () => {
    vi.mocked(http.get).mockResolvedValue({ data: mockNPCs })

    const manager = new NPCManager()
    await manager.loadNPCs('forest-1')

    expect(manager.setActiveNPC('unknown')).toBeNull()
  })

  test('getNPCTeachingTopics returns teaches + topics', async () => {
    vi.mocked(http.get).mockResolvedValue({ data: mockNPCs })

    const manager = new NPCManager()
    await manager.loadNPCs('forest-1')

    const topics = manager.getNPCTeachingTopics('npc-wizard')
    expect(topics).toContain('vocabulary')
    expect(topics).toContain('colors')
    expect(topics).toContain('animals')
    expect(topics[0]).toBe('vocabulary')
  })

  test('getNPCTeachingTopics returns empty array for unknown NPC', async () => {
    vi.mocked(http.get).mockResolvedValue({ data: mockNPCs })

    const manager = new NPCManager()
    await manager.loadNPCs('forest-1')

    expect(manager.getNPCTeachingTopics('unknown')).toEqual([])
  })

  test('loadNPCs clears previous NPCs', async () => {
    vi.mocked(http.get)
      .mockResolvedValueOnce({ data: mockNPCs })
      .mockResolvedValueOnce({ data: [mockNPCs[0]] })

    const manager = new NPCManager()
    await manager.loadNPCs('forest-1')
    expect(manager.getNPC('npc-merchant')).not.toBeNull()

    await manager.loadNPCs('village-1')
    expect(manager.getNPC('npc-merchant')).toBeNull()
    expect(manager.getNPC('npc-wizard')).not.toBeNull()
  })
})
