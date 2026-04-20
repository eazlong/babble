import { test, expect, vi, beforeEach, describe } from 'vitest'

// Mock CocosCreator module
const mockLabel = { string: '' }
const mockProgressBar = { progress: 0 }
const createMockNode = (name: string) => ({
  name,
  children: [
    { active: false, getComponent: () => ({ string: '' }) },
    { active: false, getComponent: () => ({ string: '' }) },
    { active: false, getComponent: () => ({ string: '' }) },
    { active: false, getComponent: () => ({ string: '' }) },
    { active: false, getComponent: () => ({ string: '' }) },
  ],
  active: false,
  getComponent: vi.fn(() => name.includes('Label') ? mockLabel : name.includes('Progress') ? mockProgressBar : null),
  getChildByName: vi.fn((childName: string) => {
    if (childName === 'StarRating' || childName === 'SubQuestContainer' || childName === 'BadgeContainer' || childName === 'BadgeListContainer') {
      return {
        children: [
          { active: false, getComponent: () => ({ string: '' }) },
          { active: false, getComponent: () => ({ string: '' }) },
          { active: false, getComponent: () => ({ string: '' }) },
        ],
        active: false,
      }
    }
    return { active: false, getComponent: vi.fn(() => mockLabel) }
  }),
})

vi.mock('cc', () => ({
  Label: class {},
  Node: class {
    name: string
    children: any[]
    active = false
    getComponent = vi.fn()
    getChildByName = vi.fn()
    constructor(name: string) {
      const m = createMockNode(name)
      this.name = name
      this.children = m.children
      this.getComponent = m.getComponent
      this.getChildByName = m.getChildByName
    }
  },
  ProgressBar: class {},
  tween: vi.fn(() => ({
    to: vi.fn(function (this: any) { return this }),
    start: vi.fn(),
    delay: vi.fn(function (this: any) { return this }),
    call: vi.fn(function (this: any) { return this }),
  })),
  Vec3: class {
    constructor(public x = 0, public y = 0, public z = 0) {}
  },
  Sprite: class {},
}))

import { QuestUI } from '../QuestUI'

describe('QuestUI', () => {
  let rootNode: any

  beforeEach(() => {
    vi.clearAllMocks()
    rootNode = {
      getChildByName: vi.fn((name: string) => {
        const node = createMockNode(name)
        if (name === 'QuestTitle' || name === 'QuestDesc' || name === 'QuestProgress') {
          node.getComponent = vi.fn(() => mockLabel)
        }
        if (name === 'QuestProgressBar') {
          node.getComponent = vi.fn(() => mockProgressBar)
        }
        return node
      }),
    }
  })

  test('displays quest with bilingual title', () => {
    const ui = new QuestUI(rootNode)
    ui.displayQuest({
      title: '寻找宝藏',
      title_en: 'Find the Treasure',
      description: '在森林里找到三个宝藏',
      progress: 1,
      total: 3,
      reward_lxp: 50,
      star_rating: 3,
    })

    expect(mockLabel.string).toBe('寻找宝藏 / Find the Treasure')
  })

  test('displays progress and LXP reward', () => {
    const ui = new QuestUI(rootNode)
    ui.displayQuest({
      title: '任务',
      title_en: 'Quest',
      description: '描述',
      progress: 2,
      total: 5,
      reward_lxp: 30,
      star_rating: 0,
    })

    expect(mockLabel.string).toContain('2/5')
    expect(mockLabel.string).toContain('30 LXP')
  })

  test('updates progress bar', () => {
    const ui = new QuestUI(rootNode)
    ui.displayQuest({
      title: 't',
      title_en: 't',
      description: 'd',
      progress: 0,
      total: 10,
      reward_lxp: 0,
      star_rating: 0,
    })

    expect(mockProgressBar.progress).toBe(0)
  })

  test('updateProgress updates both label and progress bar', () => {
    const ui = new QuestUI(rootNode)
    ui.displayQuest({
      title: 't',
      title_en: 't',
      description: 'd',
      progress: 0,
      total: 10,
      reward_lxp: 0,
      star_rating: 0,
    })

    ui.updateProgress(7, 10)
    expect(mockProgressBar.progress).toBe(0.7)
  })

  test('hide sets panel inactive', () => {
    const ui = new QuestUI(rootNode)
    ui.displayQuest({
      title: 't',
      title_en: 't',
      description: 'd',
      progress: 0,
      total: 1,
      reward_lxp: 0,
      star_rating: 0,
    })

    ui.hide()
    expect(rootNode.getChildByName('QuestPanel')().active).toBe(false)
  })
})
