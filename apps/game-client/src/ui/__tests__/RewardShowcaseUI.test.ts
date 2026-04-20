import { test, expect, vi, beforeEach, describe } from 'vitest'

// Mock CocosCreator module
const mockLabel = { string: '', color: { r: 255, g: 255, b: 255, a: 255 } }
const createMockNode = (name: string) => ({
  name,
  children: [
    { active: false, getComponent: () => ({ ...mockLabel }) },
    { active: false, getComponent: () => ({ ...mockLabel }) },
    { active: false, getComponent: () => ({ ...mockLabel }) },
  ],
  active: false,
  getComponent: vi.fn(() => mockLabel),
  addChild: vi.fn(),
  setPosition: vi.fn(),
  setScale: vi.fn(),
  destroy: vi.fn(),
  addComponent: vi.fn(() => ({})),
  getChildByName: vi.fn(() => ({ active: false, getComponent: vi.fn(() => mockLabel) })),
})

const mockTweenCalls: any[] = []

vi.mock('cc', () => ({
  Label: class {},
  Node: class {
    name: string
    children: any[]
    active = false
    getComponent = vi.fn()
    addChild = vi.fn()
    setPosition = vi.fn()
    setScale = vi.fn()
    destroy = vi.fn()
    addComponent = vi.fn(() => ({}))
    getChildByName = vi.fn()
    constructor(name: string) {
      const m = createMockNode(name)
      this.name = name
      this.children = m.children
      this.getComponent = m.getComponent
      this.addChild = m.addChild
      this.setPosition = m.setPosition
      this.setScale = m.setScale
      this.destroy = m.destroy
      this.addComponent = m.addComponent
      this.getChildByName = m.getChildByName
    }
  },
  tween: vi.fn(() => {
    const chain = {
      to: vi.fn(function (this: any) { mockTweenCalls.push('to'); return this }),
      start: vi.fn(function (this: any) { mockTweenCalls.push('start'); return this }),
      delay: vi.fn(function (this: any) { mockTweenCalls.push('delay'); return this }),
      call: vi.fn(function (this: any) { mockTweenCalls.push('call'); return this }),
    }
    return chain
  }),
  Vec3: class {
    constructor(public x = 0, public y = 0, public z = 0) {}
  },
  Sprite: class {},
}))

import { RewardShowcaseUI } from '../RewardShowcaseUI'

describe('RewardShowcaseUI', () => {
  let rootNode: any

  beforeEach(() => {
    vi.clearAllMocks()
    mockTweenCalls.length = 0
    rootNode = {
      getChildByName: vi.fn((name: string) => {
        const node = createMockNode(name)
        if (name === 'LXPLabel' || name === 'LevelLabel') {
          node.getComponent = vi.fn(() => mockLabel)
        }
        return node
      }),
    }
  })

  test('updateLXP displays current LXP and level', () => {
    const ui = new RewardShowcaseUI(rootNode)
    ui.updateLXP({ current: 150, to_next_level: 200, level: 3 })

    expect(mockLabel.string).toContain('150/200')
    expect(mockLabel.string).toContain('Level 3')
  })

  test('show and hide toggle container visibility', () => {
    const ui = new RewardShowcaseUI(rootNode)
    ui.hide()
    expect(rootNode.getChildByName('BadgeContainer')().active).toBe(false)

    ui.show()
    expect(rootNode.getChildByName('BadgeContainer')()).toBeDefined()
  })

  test('showNewBadge creates animated badge node', () => {
    const ui = new RewardShowcaseUI(rootNode)
    ui.showNewBadge({
      badge_id: 'badge-test',
      name: 'Test Badge',
      description: 'A test badge',
      icon_ref: 'test_icon',
      unlock_condition: 'Complete 3 quests',
      reward_preview: '+50 LXP',
    })

    expect(mockTweenCalls).toContain('to')
    expect(mockTweenCalls).toContain('start')
  })

  test('showBadgeUnlockAnimation creates animation for earned badge', () => {
    const ui = new RewardShowcaseUI(rootNode)
    const badge = {
      badge_id: 'badge-forest',
      name: 'Forest Badge',
      description: 'Complete the forest',
      icon_ref: 'forest_icon',
      unlock_condition: 'Complete forest scene',
      reward_preview: '+100 LXP',
    }

    ui.setBadges([badge], [])
    mockTweenCalls.length = 0

    ui.showBadgeUnlockAnimation('badge-forest')

    expect(mockTweenCalls).toContain('to')
    expect(mockTweenCalls).toContain('start')
  })

  test('showBadgeUnlockAnimation does nothing for unknown badge', () => {
    const ui = new RewardShowcaseUI(rootNode)
    ui.setBadges([], [])
    mockTweenCalls.length = 0

    ui.showBadgeUnlockAnimation('nonexistent')

    expect(mockTweenCalls).toHaveLength(0)
  })

  test('setBadges stores earned and unearned badges', () => {
    const ui = new RewardShowcaseUI(rootNode)
    const earned = [{
      badge_id: 'badge-a', name: 'A', description: 'Badge A', icon_ref: 'a',
      unlock_condition: '', reward_preview: '',
    }]
    const unearned = [{
      badge_id: 'badge-b', name: 'B', description: 'Badge B', icon_ref: 'b',
      unlock_condition: 'Complete quest', reward_preview: '',
    }]

    ui.setBadges(earned, unearned)

    expect((ui as any).earnedBadges).toHaveLength(1)
    expect((ui as any).unearnedBadges).toHaveLength(1)
  })
})
