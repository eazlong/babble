import { test, expect, vi, beforeEach, describe } from 'vitest'
import { GameWorld } from '../GameWorld'
import { http } from '../../network/HttpClient'

vi.mock('../../network/HttpClient', () => ({
  http: {
    get: vi.fn(),
    post: vi.fn(),
  },
}))

const mockScene = {
  scene_id: 'forest-1',
  scene_name: '魔法森林',
  scene_type: 'forest',
  visual_assets_ref: 'forest_bg',
  ambient_audio_ref: 'forest_ambience',
  description: '魔法森林',
  npcs: [],
  vocabulary_focus: [],
  tasks: [],
  badge_id: 'badge-forest',
  required_lxp: 50,
  interactable_zones: [],
}

describe('GameWorld', () => {
  beforeEach(() => {
    vi.clearAllMocks()
  })

  test('provides access to SceneManager and NPCManager', () => {
    const world = new GameWorld()
    expect(world.getSceneManager()).toBeDefined()
    expect(world.getNPCManager()).toBeDefined()
  })

  test('canEnterScene returns true when user has enough LXP', async () => {
    vi.mocked(http.get).mockResolvedValue({ data: mockScene })

    const world = new GameWorld()
    await world.enterScene('forest-1')

    expect(world.canEnterScene('forest-1')).toBe(true)
  })

  test('canEnterScene returns false when user lacks LXP', async () => {
    vi.mocked(http.get).mockResolvedValue({ data: mockScene })

    const world = new GameWorld()
    await world.enterScene('forest-1')

    // The canEnterScene checks storyProgress.total_lxp which starts at 0
    // required_lxp is 50, so this should be false
    expect(world.canEnterScene('forest-1')).toBe(false)
  })

  test('advanceStory updates completed quests and LXP', async () => {
    vi.mocked(http.get).mockResolvedValue({ data: mockScene })

    const world = new GameWorld()
    await world.enterScene('forest-1')

    world.advanceStory('quest-1', 30)

    const progress = world.getStoryProgress()
    expect(progress.completed_quests).toContain('quest-1')
    expect(progress.total_lxp).toBe(30)
  })

  test('advanceStory does not duplicate quest completion', async () => {
    vi.mocked(http.get).mockResolvedValue({ data: mockScene })

    const world = new GameWorld()
    await world.enterScene('forest-1')

    world.advanceStory('quest-1', 30)
    world.advanceStory('quest-1', 20)

    const progress = world.getStoryProgress()
    expect(progress.completed_quests.filter((q) => q === 'quest-1')).toHaveLength(1)
    expect(progress.total_lxp).toBe(50)
  })

  test('getStoryProgress returns a copy', async () => {
    vi.mocked(http.get).mockResolvedValue({ data: mockScene })

    const world = new GameWorld()
    await world.enterScene('forest-1')

    const p1 = world.getStoryProgress()
    p1.completed_quests.push('hacked')

    const p2 = world.getStoryProgress()
    expect(p2.completed_quests).not.toContain('hacked')
  })

  test('hasBadge returns correct status', async () => {
    const world = new GameWorld()
    expect(world.hasBadge('badge-forest')).toBe(false)

    world.addBadge('badge-forest')
    expect(world.hasBadge('badge-forest')).toBe(true)
  })

  test('addBadge does not duplicate badges', () => {
    const world = new GameWorld()
    world.addBadge('badge-forest')
    world.addBadge('badge-forest')

    expect(world.getEarnedBadges()).toHaveLength(1)
  })

  test('getEarnedBadges returns a copy', () => {
    const world = new GameWorld()
    world.addBadge('badge-forest')

    const badges = world.getEarnedBadges()
    badges.push('fake-badge')

    expect(world.getEarnedBadges()).not.toContain('fake-badge')
  })

  test('enterScene updates current_scene_id in story progress', async () => {
    vi.mocked(http.get).mockResolvedValue({ data: mockScene })

    const world = new GameWorld()
    await world.enterScene('forest-1')

    expect(world.getStoryProgress().current_scene_id).toBe('forest-1')
  })

  test('getCurrentQuests returns a copy', () => {
    const world = new GameWorld()
    const quests = world.getCurrentQuests()
    quests.push({
      quest_id: 'hacked',
      title: 'hacked',
      title_en: 'hacked',
      description: '',
      target_npc_id: '',
      required_dialogue_turns: 0,
      reward_lxp: 0,
    })

    expect(world.getCurrentQuests()).toHaveLength(0)
  })
})
