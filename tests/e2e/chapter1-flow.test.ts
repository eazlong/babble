import { test, expect } from './fixtures'

test.describe('Chapter 1: Complete Flow', () => {
  test('Forest -> Library -> Garden full progression', async ({ page }) => {
    await page.goto('/')

    // === Scene 1: Spirit Forest ===
    await page.getByText('精灵森林').click()
    await expect(page.getByTestId('scene-title')).toBeVisible()

    // Quest 1: Greet Oakley
    await page.getByTestId('npc-oakley').click()
    await page.getByTestId('accept-quest').click()
    await expect(page.getByTestId('quest-objective')).toBeVisible()
    await expect(page.getByTestId('quest-objective')).toContainText('打招呼')

    await page.evaluate(() => {
      ;(window as any).__mockTextInput__('Hello, Oakley!')
    })
    await page.waitForTimeout(1000)
    await page.evaluate(() => {
      ;(window as any).__mockCompleteTurn__()
    })
    await expect(page.getByTestId('quest-complete')).toBeVisible()

    // Quest 2: Activate Flowers (color vocabulary)
    await page.getByTestId('flower-puzzle').click()
    await page.getByTestId('accept-quest').click()
    await page.evaluate(() => {
      ;(window as any).__mockTextInput__('The flower is red')
    })
    await page.waitForTimeout(1000)
    await page.evaluate(() => {
      ;(window as any).__mockCompleteTurn__()
    })
    await expect(page.getByTestId('quest-complete')).toBeVisible()

    // Quest 3: Open Treasure Chest (number vocabulary)
    await page.getByTestId('treasure-chest').click()
    await page.getByTestId('accept-quest').click()
    await page.evaluate(() => {
      ;(window as any).__mockTextInput__('One two three open')
    })
    await page.waitForTimeout(1000)
    await page.evaluate(() => {
      ;(window as any).__mockCompleteTurn__()
    })
    await expect(page.getByTestId('quest-complete')).toBeVisible()

    // Forest Badge should be unlocked
    await expect(page.getByTestId('badge-unlocked')).toBeVisible()
    await expect(page.getByTestId('badge-unlocked')).toContainText('精灵森林探索者')

    // === Scene 2: Spell Library ===
    await page.getByTestId('next-scene').click()
    await expect(page.getByText('咒语图书馆')).toBeVisible()

    // Quest 1: Organize Books
    await page.getByTestId('book-puzzle').click()
    await page.getByTestId('accept-quest').click()
    await page.evaluate(() => {
      ;(window as any).__mockTextInput__('The big blue book')
    })
    await page.waitForTimeout(1000)
    await page.evaluate(() => {
      ;(window as any).__mockCompleteTurn__()
    })
    await expect(page.getByTestId('quest-complete')).toBeVisible()

    // Quest 2: Follow Commands
    await page.getByTestId('command-puzzle').click()
    await page.getByTestId('accept-quest').click()
    await page.evaluate(() => {
      ;(window as any).__mockTextInput__('Open the book please')
    })
    await page.waitForTimeout(1000)
    await page.evaluate(() => {
      ;(window as any).__mockCompleteTurn__()
    })
    await expect(page.getByTestId('quest-complete')).toBeVisible()

    // Quest 3: Practice Dialogue with Luna
    await page.getByTestId('npc-luna').click()
    await page.getByTestId('accept-quest').click()
    await page.evaluate(() => {
      ;(window as any).__mockTextInput__('What is your name')
    })
    await page.waitForTimeout(1000)
    await page.evaluate(() => {
      ;(window as any).__mockCompleteTurn__()
    })
    await expect(page.getByTestId('quest-complete')).toBeVisible()

    // Library Badge should be unlocked
    await expect(page.getByTestId('badge-unlocked')).toHaveCount(2)
    await expect(page.getByTestId('badge-unlocked').last()).toContainText('咒语图书馆学者')

    // === Scene 3: Rainbow Garden ===
    await page.getByTestId('next-scene').click()
    await expect(page.getByText('彩虹花园')).toBeVisible()

    // Quest 1: Fix Weather Crystal
    await page.getByTestId('weather-crystal').click()
    await page.getByTestId('accept-quest').click()
    await page.evaluate(() => {
      ;(window as any).__mockTextInput__('It is sunny today')
    })
    await page.waitForTimeout(1000)
    await page.evaluate(() => {
      ;(window as any).__mockCompleteTurn__()
    })
    await expect(page.getByTestId('quest-complete')).toBeVisible()

    // Quest 2: Find Lost Animals
    await page.getByTestId('animal-search').click()
    await page.getByTestId('accept-quest').click()
    await page.evaluate(() => {
      ;(window as any).__mockTextInput__('I see a cat and a dog')
    })
    await page.waitForTimeout(1000)
    await page.evaluate(() => {
      ;(window as any).__mockCompleteTurn__()
    })
    await expect(page.getByTestId('quest-complete')).toBeVisible()

    // Quest 3: Plant Magic Flowers
    await page.getByTestId('plant-flower').click()
    await page.getByTestId('accept-quest').click()
    await page.evaluate(() => {
      ;(window as any).__mockTextInput__('I plant a red flower')
    })
    await page.waitForTimeout(1000)
    await page.evaluate(() => {
      ;(window as any).__mockCompleteTurn__()
    })
    await expect(page.getByTestId('quest-complete')).toBeVisible()

    // Garden Badge should be unlocked
    await expect(page.getByTestId('badge-unlocked')).toHaveCount(3)
    await expect(page.getByTestId('badge-unlocked').last()).toContainText('彩虹花园守护者')

    // Apprentice Title should unlock when all 3 badges earned
    await expect(page.getByTestId('title-unlocked')).toBeVisible()
    await expect(page.getByTestId('title-unlocked')).toContainText('Apprentice')
  })
})

test.describe('Chapter 1: Spirit Forest Vocabulary', () => {
  test('greeting vocabulary matching', async ({ page }) => {
    await page.goto('/')
    await page.getByText('精灵森林').click()
    await page.getByTestId('npc-oakley').click()
    await page.getByTestId('accept-quest').click()

    // Test valid greetings are recognized
    const greetings = ['Hello', 'Hi', 'Good morning', 'Goodbye', 'Bye']
    for (const greeting of greetings) {
      await page.evaluate((g) => {
        ;(window as any).__mockTextInput__(g)
      }, greeting)
      await page.waitForTimeout(500)
      const match = await page.getByTestId('vocab-match')
      await expect(match).toBeVisible()
    }
  })

  test('color vocabulary matching', async ({ page }) => {
    await page.goto('/')
    await page.getByText('精灵森林').click()
    await page.getByTestId('flower-puzzle').click()
    await page.getByTestId('accept-quest').click()

    const colors = ['red', 'blue', 'green', 'yellow', 'orange', 'purple']
    for (const color of colors) {
      await page.evaluate((c) => {
        ;(window as any).__mockTextInput__(`The flower is ${color}`)
      }, color)
      await page.waitForTimeout(500)
      const match = await page.getByTestId('color-recognized')
      await expect(match).toBeVisible()
      await expect(match).toContainText(color)
    }
  })

  test('number vocabulary matching', async ({ page }) => {
    await page.goto('/')
    await page.getByText('精灵森林').click()
    await page.getByTestId('treasure-chest').click()
    await page.getByTestId('accept-quest').click()

    const numbers = ['one', 'two', 'three', 'four', 'five', 'ten', 'twenty']
    for (const num of numbers) {
      await page.evaluate((n) => {
        ;(window as any).__mockTextInput__(`I say ${num}`)
      }, num)
      await page.waitForTimeout(500)
      const match = await page.getByTestId('number-recognized')
      await expect(match).toBeVisible()
    }
  })
})

test.describe('Chapter 1: Spirit Coach Intervention', () => {
  test('coach gives hints on silence', async ({ page }) => {
    await page.goto('/')
    await page.getByText('精灵森林').click()
    await page.getByTestId('npc-oakley').click()
    await page.getByTestId('accept-quest').click()

    // Simulate silence timeout (mock advances time)
    await page.evaluate(() => {
      ;(window as any).__mockSilenceTimeout__()
    })
    await page.waitForTimeout(1000)

    // Coach hint bubble should appear
    const coachHint = page.getByTestId('coach-hint')
    await expect(coachHint).toBeVisible()

    // Hint should contain curriculum-guided suggestion
    const hintContent = await coachHint.textContent()
    expect(hintContent).toBeTruthy()
    expect(hintContent?.length).toBeGreaterThan(20)
  })

  test('coach encourages on errors', async ({ page }) => {
    await page.goto('/')
    await page.getByText('精灵森林').click()
    await page.getByTestId('npc-oakley').click()
    await page.getByTestId('accept-quest').click()

    // Submit incorrect/weak answer
    await page.evaluate(() => {
      ;(window as any).__mockTextInput__('...')
    })
    await page.waitForTimeout(1000)

    // Coach should show encouragement
    const coachEncourage = page.getByTestId('coach-encouragement')
    await expect(coachEncourage).toBeVisible()
    const text = await coachEncourage.textContent()
    expect(text).toBeTruthy()
  })

  test('coach detects curriculum vocabulary usage', async ({ page }) => {
    await page.goto('/')
    await page.getByText('精灵森林').click()
    await page.getByTestId('npc-oakley').click()
    await page.getByTestId('accept-quest').click()

    // Use curriculum vocabulary (greetings category)
    await page.evaluate(() => {
      ;(window as any).__mockTextInput__('Hello, good morning! How are you?')
    })
    await page.waitForTimeout(1000)

    // Coach should acknowledge curriculum vocab usage
    const coachDetect = page.getByTestId('coach-vocab-detected')
    await expect(coachDetect).toBeVisible()

    // Should show matched categories
    const categories = await page.getByTestId('vocab-category')
    await expect(categories.first()).toBeVisible()
  })
})

test.describe('Chapter 1: Difficulty Reduction', () => {
  test('3 consecutive errors triggers difficulty reduction', async ({ page }) => {
    await page.goto('/')
    await page.getByText('精灵森林').click()
    await page.getByTestId('npc-oakley').click()
    await page.getByTestId('accept-quest').click()

    // Simulate 3 consecutive errors
    for (let i = 0; i < 3; i++) {
      await page.evaluate(() => {
        ;(window as any).__mockWrongAnswer__()
      })
      await page.waitForTimeout(500)
    }

    // Difficulty indicator should show reduced level
    const diffIndicator = page.getByTestId('difficulty-level')
    await expect(diffIndicator).toBeVisible()
    const diffText = await diffIndicator.textContent()
    expect(diffText).toContain('Easy')

    // Coach should explain the difficulty change
    const coachNotice = page.getByTestId('coach-difficulty-change')
    await expect(coachNotice).toBeVisible()
  })

  test('correct answer resets error streak', async ({ page }) => {
    await page.goto('/')
    await page.getByText('精灵森林').click()
    await page.getByTestId('npc-oakley').click()
    await page.getByTestId('accept-quest').click()

    // Make 2 errors (not enough to trigger reduction)
    for (let i = 0; i < 2; i++) {
      await page.evaluate(() => {
        ;(window as any).__mockWrongAnswer__()
      })
      await page.waitForTimeout(500)
    }

    // Then get a correct answer
    await page.evaluate(() => {
      ;(window as any).__mockCorrectAnswer__()
    })
    await page.waitForTimeout(1000)

    // Error streak should be reset; difficulty should remain normal
    const diffIndicator = page.getByTestId('difficulty-level')
    await expect(diffIndicator).toBeVisible()
    const diffText = await diffIndicator.textContent()
    expect(diffText).not.toContain('Easy')

    // Streak badge should show reset
    const streakStatus = page.getByTestId('error-streak-status')
    await expect(streakStatus).toContainText('0')
  })
})

test.describe('Chapter 1: Badge Collection & Apprentice Title', () => {
  test('Forest badge unlocks when all sub-quests complete', async ({ page }) => {
    await page.goto('/')
    await page.getByText('精灵森林').click()

    // Complete all 3 forest sub-quests
    const forestQuests = [
      { trigger: 'npc-oakley', input: 'Hello Oakley' },
      { trigger: 'flower-puzzle', input: 'Red flower' },
      { trigger: 'treasure-chest', input: 'One two three' },
    ]

    for (const quest of forestQuests) {
      await page.getByTestId(quest.trigger).click()
      await page.getByTestId('accept-quest').click()
      await page.evaluate((inp) => {
        ;(window as any).__mockTextInput__(inp)
      }, quest.input)
      await page.waitForTimeout(500)
      await page.evaluate(() => {
        ;(window as any).__mockCompleteTurn__()
      })
      await expect(page.getByTestId('quest-complete')).toBeVisible()
    }

    // Badge should unlock
    await expect(page.getByTestId('badge-forest')).toBeVisible()
    await expect(page.getByTestId('badge-forest')).toContainText('精灵森林探索者')
  })

  test('Apprentice title unlocks when all 3 badges earned', async ({ page }) => {
    await page.goto('/')

    // Earn Forest badge
    await page.getByText('精灵森林').click()
    const forestTriggers = ['npc-oakley', 'flower-puzzle', 'treasure-chest']
    for (const trigger of forestTriggers) {
      await page.getByTestId(trigger).click()
      await page.getByTestId('accept-quest').click()
      await page.evaluate(() => {
        ;(window as any).__mockTextInput__('test')
      })
      await page.waitForTimeout(500)
      await page.evaluate(() => {
        ;(window as any).__mockCompleteTurn__()
      })
    }
    await expect(page.getByTestId('badge-forest')).toBeVisible()

    // Earn Library badge
    await page.getByTestId('next-scene').click()
    await expect(page.getByText('咒语图书馆')).toBeVisible()
    const libraryTriggers = ['book-puzzle', 'command-puzzle', 'npc-luna']
    for (const trigger of libraryTriggers) {
      await page.getByTestId(trigger).click()
      await page.getByTestId('accept-quest').click()
      await page.evaluate(() => {
        ;(window as any).__mockTextInput__('test')
      })
      await page.waitForTimeout(500)
      await page.evaluate(() => {
        ;(window as any).__mockCompleteTurn__()
      })
    }
    await expect(page.getByTestId('badge-library')).toBeVisible()

    // Earn Garden badge
    await page.getByTestId('next-scene').click()
    await expect(page.getByText('彩虹花园')).toBeVisible()
    const gardenTriggers = ['weather-crystal', 'animal-search', 'plant-flower']
    for (const trigger of gardenTriggers) {
      await page.getByTestId(trigger).click()
      await page.getByTestId('accept-quest').click()
      await page.evaluate(() => {
        ;(window as any).__mockTextInput__('test')
      })
      await page.waitForTimeout(500)
      await page.evaluate(() => {
        ;(window as any).__mockCompleteTurn__()
      })
    }
    await expect(page.getByTestId('badge-garden')).toBeVisible()

    // Apprentice title should unlock
    await expect(page.getByTestId('title-unlocked')).toBeVisible()
    await expect(page.getByTestId('title-unlocked')).toContainText('Apprentice')

    // Rewards panel should show all 3 badges
    await page.getByTestId('open-rewards').click()
    const badgeItems = page.getByTestId('badge-item')
    await expect(badgeItems).toHaveCount(3)
  })
})
