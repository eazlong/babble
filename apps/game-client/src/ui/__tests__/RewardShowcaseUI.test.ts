import { test, expect, vi, beforeEach, describe } from 'vitest'

// Mock CocosCreator module
const tweenCalls: string[] = []

vi.mock('cc', () => ({
  Label: class {},
  Node: class {
    name: string
    children: any[]
    active = false
    _position: { x: number; y: number; z: number } = { x: 0, y: 0, z: 0 }
    _scale: { x: number; y: number; z: number } = { x: 1, y: 1, z: 1 }
    _label = { string: '', color: { r: 255, g: 255, b: 255, a: 255 } }
    _sprite: any = null

    constructor(name: string) {
      this.name = name
      this.children = [
        { active: false, getComponent: () => ({ string: '', color: { r: 255, g: 255, b: 255, a: 255 } }) },
        { active: false, getComponent: () => ({ string: '', color: { r: 255, g: 255, b: 255, a: 255 } }) },
        { active: false, getComponent: () => ({ string: '', color: { r: 255, g: 255, b: 255, a: 255 } }) },
      ]
    }

    getComponent(_cls: any) {
      return this._label
    }

    setPosition(pos: any) {
      this._position = { x: pos.x, y: pos.y, z: pos.z }
    }

    setScale(s: any) {
      this._scale = { x: s.x, y: s.y, z: s.z }
    }

    addChild(_child: any) {}

    addComponent(cls: any) {
      if (cls.name === 'Sprite') {
        this._sprite = {}
        return this._sprite
      }
      return {}
    }

    destroy() {}

    getChildByName(_name: string) {
      return { active: false, getComponent: () => ({ string: '', color: { r: 255, g: 255, b: 255, a: 255 } }) }
    }
  },
  tween: vi.fn(() => {
    const chain = {
      to: vi.fn(function (this: any) { tweenCalls.push('to'); return this }),
      start: vi.fn(function (this: any) { tweenCalls.push('start'); return this }),
      delay: vi.fn(function (this: any) { tweenCalls.push('delay'); return this }),
      call: vi.fn(function (this: any) { tweenCalls.push('call'); return this }),
    }
    return chain
  }),
  Vec3: class {
    constructor(public x = 0, public y = 0, public z = 0) {}
  },
  Sprite: class {},
  Color: class {
    constructor(public r = 255, public g = 255, public b = 255, public a = 255) {}
  },
}))

import { RewardShowcaseUI } from '../RewardShowcaseUI'

function createRootNode() {
  const labels: Record<string, { string: string }> = {
    LXPLabel: { string: '' },
    LevelLabel: { string: '' },
  }
  const badgeContainer = { active: true, children: [], addChild: vi.fn() }
  const badgeListContainer = {
    active: false,
    children: [
      { active: false, getComponent: () => ({ string: '', color: { r: 255, g: 255, b: 255, a: 255 } }) },
      { active: false, getComponent: () => ({ string: '', color: { r: 255, g: 255, b: 255, a: 255 } }) },
      { active: false, getComponent: () => ({ string: '', color: { r: 255, g: 255, b: 255, a: 255 } }) },
    ],
  }

  const rootNode = {
    getChildByName: vi.fn((name: string) => {
      if (name === 'BadgeContainer') return badgeContainer
      if (name === 'BadgeListContainer') return badgeListContainer
      return {
        active: false,
        getComponent: vi.fn(() => labels[name] || { string: '' }),
      }
    }),
    labels,
    badgeContainer,
    badgeListContainer,
  }

  return rootNode
}

describe('RewardShowcaseUI', () => {
  let rootNode: any

  beforeEach(() => {
    vi.clearAllMocks()
    tweenCalls.length = 0
    rootNode = createRootNode()
  })

  test('updateLXP displays current LXP and level', () => {
    const ui = new RewardShowcaseUI(rootNode)
    ui.updateLXP({ current: 150, to_next_level: 200, level: 3 })

    expect(rootNode.labels.LXPLabel.string).toContain('150/200')
    expect(rootNode.labels.LevelLabel.string).toContain('Level 3')
  })

  test('show and hide toggle container visibility', () => {
    const ui = new RewardShowcaseUI(rootNode)
    ui.hide()
    expect(rootNode.badgeContainer.active).toBe(false)

    ui.show()
    expect(rootNode.badgeContainer.active).toBe(true)
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

    expect(tweenCalls).toContain('to')
    expect(tweenCalls).toContain('start')
  })

  test('showBadgeUnlockAnimation creates animation for earned badge', () => {
    const ui = new RewardShowcaseUI(rootNode)
    const badge = {
      badge_id: 'badge-forest',
      name: 'Forest Badge',
      description: 'Complete the forest',
      icon_ref: 'forest_icon',
      earned_at: '2026-04-18',
      unlock_condition: 'Complete forest scene',
      reward_preview: '+100 LXP',
    }

    ui.setBadges([badge], [])
    tweenCalls.length = 0

    ui.showBadgeUnlockAnimation('badge-forest')

    expect(tweenCalls).toContain('to')
    expect(tweenCalls).toContain('start')
  })

  test('showBadgeUnlockAnimation does nothing for unknown badge', () => {
    const ui = new RewardShowcaseUI(rootNode)
    ui.setBadges([], [])
    tweenCalls.length = 0

    ui.showBadgeUnlockAnimation('nonexistent')

    expect(tweenCalls).toHaveLength(0)
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
