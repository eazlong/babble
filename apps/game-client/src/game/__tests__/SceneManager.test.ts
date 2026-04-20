import { test, expect, vi, beforeEach, describe } from 'vitest'
import { SceneManager } from '../SceneManager'
import { http } from '../../network/HttpClient'

vi.mock('../../network/HttpClient', () => ({
  http: {
    get: vi.fn(),
    post: vi.fn(),
  },
}))

const mockSceneConfig = {
  scene_id: 'forest-1',
  scene_name: '魔法森林',
  scene_type: 'forest',
  visual_assets_ref: 'forest_bg',
  ambient_audio_ref: 'forest_ambience',
  description: '一个充满魔法的森林',
  npcs: [{ npc_id: 'npc-wizard', position: { x: 100, y: 200 } }],
  vocabulary_focus: ['tree', 'magic', 'forest'],
  tasks: [
    { task_id: 'task-1', title: '寻找魔法树', title_en: 'Find the Magic Tree', description: '', required_lxp: 0 },
  ],
  badge_id: 'badge-forest',
  required_lxp: 50,
  interactable_zones: [
    { zone_id: 'zone-1', trigger_type: 'proximity' as const, action: 'enter_forest' },
  ],
}

describe('SceneManager', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  test('loads scene config from API', async () => {
    vi.mocked(http.get).mockResolvedValue({ data: mockSceneConfig })

    const manager = new SceneManager()
    const scene = await manager.loadScene('forest-1')

    expect(scene.scene_id).toBe('forest-1')
    expect(scene.description).toBe('一个充满魔法的森林')
    expect(scene.required_lxp).toBe(50)
    expect(scene.badge_id).toBe('badge-forest')
    expect(scene.vocabulary_focus).toEqual(['tree', 'magic', 'forest'])
  })

  test('throws on API error', async () => {
    vi.mocked(http.get).mockResolvedValue({ error: { code: 'NOT_FOUND', message: 'Scene not found' } })

    const manager = new SceneManager()
    await expect(manager.loadScene('invalid')).rejects.toThrow()
  })

  test('returns current scene', async () => {
    vi.mocked(http.get).mockResolvedValue({ data: mockSceneConfig })

    const manager = new SceneManager()
    await manager.loadScene('forest-1')

    const current = manager.getCurrentScene()
    expect(current).not.toBeNull()
    expect(current!.scene_id).toBe('forest-1')
  })

  test('isSceneUnlocked returns true when user has enough LXP', async () => {
    vi.mocked(http.get).mockResolvedValue({ data: mockSceneConfig })

    const manager = new SceneManager()
    await manager.loadScene('forest-1')

    expect(manager.isSceneUnlocked(100)).toBe(true)
    expect(manager.isSceneUnlocked(50)).toBe(true)
  })

  test('isSceneUnlocked returns false when user lacks LXP', async () => {
    vi.mocked(http.get).mockResolvedValue({ data: mockSceneConfig })

    const manager = new SceneManager()
    await manager.loadScene('forest-1')

    expect(manager.isSceneUnlocked(30)).toBe(false)
  })

  test('isSceneUnlocked returns false when no scene loaded', () => {
    const manager = new SceneManager()
    expect(manager.isSceneUnlocked(999)).toBe(false)
  })

  test('getSceneProgress returns null when no scene loaded', () => {
    const manager = new SceneManager()
    expect(manager.getSceneProgress()).toBeNull()
  })

  test('getSceneProgress returns null when no progress recorded', async () => {
    vi.mocked(http.get).mockResolvedValue({ data: mockSceneConfig })

    const manager = new SceneManager()
    await manager.loadScene('forest-1')

    expect(manager.getSceneProgress()).toBeNull()
  })

  test('updateSceneProgress stores and retrieves progress', async () => {
    vi.mocked(http.get).mockResolvedValue({ data: mockSceneConfig })

    const manager = new SceneManager()
    await manager.loadScene('forest-1')

    const progress = {
      scene_id: 'forest-1',
      completed_tasks: ['task-1'],
      total_tasks: 3,
      badge_earned: false,
      visited_at: '2026-04-18T00:00:00Z',
    }
    manager.updateSceneProgress(progress)

    expect(manager.getSceneProgress()).toEqual(progress)
  })

  test('returns available NPCs from current scene', async () => {
    vi.mocked(http.get).mockResolvedValue({ data: mockSceneConfig })

    const manager = new SceneManager()
    await manager.loadScene('forest-1')

    const npcs = manager.getAvailableNPCs()
    expect(npcs).toHaveLength(1)
    expect(npcs[0].npc_id).toBe('npc-wizard')
  })
})
