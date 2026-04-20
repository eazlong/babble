import { test, expect, vi, beforeEach, describe } from 'vitest'

// Mock CocosCreator module with separate label instances per node
const labelInstances: Record<string, { string: string }> = {}

const mockProgressBarInstance = { progress: 0 }

function getOrCreateLabel(name: string) {
  if (!labelInstances[name]) {
    labelInstances[name] = { string: '' }
  }
  return labelInstances[name]
}

vi.mock('cc', () => ({
  Label: class {},
  Node: class {
    name: string
    children: any[]
    active = false
    _labels: Record<string, { string: string }> = {}
    _progress: { progress: number } = { progress: 0 }

    constructor(name: string) {
      this.name = name
      this.children = [
        { active: false, getComponent: () => ({ string: '' }) },
        { active: false, getComponent: () => ({ string: '' }) },
        { active: false, getComponent: () => ({ string: '' }) },
        { active: false, getComponent: () => ({ string: '' }) },
        { active: false, getComponent: () => ({ string: '' }) },
      ]
    }

    getComponent(_cls: any) {
      if (this.name.includes('Progress')) {
        return mockProgressBarInstance
      }
      return getOrCreateLabel(this.name)
    }

    getChildByName(childName: string) {
      const child = new (vi.mocked('cc').Node as any)(childName)
      child.getComponent = function () {
        if (childName.includes('Progress')) {
          return mockProgressBarInstance
        }
        return getOrCreateLabel(childName)
      }
      return child
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

// Create a proper mock root node with tracked labels
function createRootNode() {
  const labels: Record<string, { string: string }> = {
    QuestTitle: { string: '' },
    QuestDesc: { string: '' },
    QuestProgress: { string: '' },
  }
  const progressBar = { progress: 0 }

  const starRatingChildren = [
    { active: false },
    { active: false },
    { active: false },
    { active: false },
    { active: false },
  ]
  const subQuestChildren = [
    { active: false, getComponent: () => ({ string: '' }) },
    { active: false, getComponent: () => ({ string: '' }) },
    { active: false, getComponent: () => ({ string: '' }) },
  ]

  const starRatingNode = {
    children: starRatingChildren,
    active: false,
  }
  const subQuestNode = {
    children: subQuestChildren,
    active: false,
  }

  const questPanelNode = {
    active: false,
    children: [],
    getChildByName: vi.fn(() => ({ active: false })),
    getComponent: vi.fn(() => null),
  }

  const rootNode = {
    getChildByName: vi.fn((name: string) => {
      if (name === 'QuestPanel') return questPanelNode
      if (name === 'StarRating') return starRatingNode
      if (name === 'SubQuestContainer') return subQuestNode
      return {
        active: false,
        getComponent: vi.fn(() => {
          if (name === 'QuestProgressBar') return progressBar
          return labels[name] || { string: '' }
        }),
      }
    }),
    labels,
    progressBar,
    questPanel: questPanelNode,
    starRating: starRatingNode,
    subQuest: subQuestNode,
  }

  return rootNode
}

describe('QuestUI', () => {
  let rootNode: any

  beforeEach(() => {
    vi.clearAllMocks()
    rootNode = createRootNode()
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

    expect(rootNode.labels.QuestTitle.string).toBe('寻找宝藏 / Find the Treasure')
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

    expect(rootNode.labels.QuestProgress.string).toContain('2/5')
    expect(rootNode.labels.QuestProgress.string).toContain('30 LXP')
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

    expect(rootNode.progressBar.progress).toBe(0)
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
    expect(rootNode.progressBar.progress).toBe(0.7)
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
    expect(rootNode.questPanel.active).toBe(false)
  })
})
