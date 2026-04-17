import { test, expect } from './fixtures'

test.describe('Reward & Drop E2E', () => {
  test('completing dialogue awards LXP', async ({ page }) => {
    await page.goto('/')

    // Start a dialogue turn
    await page.getByTestId('start-dialogue').click()
    await page.waitForTimeout(2000)

    // Complete the turn
    await page.evaluate(() => {
      ;(window as any).__mockCompleteTurn__()
    })

    // LXP should be awarded
    const lxpEarned = await page.getByTestId('lxp-earned')
    await expect(lxpEarned).toBeVisible()

    const lxpValue = await lxpEarned.textContent()
    expect(Number(lxpValue?.replace(/\D/g, ''))).toBeGreaterThan(0)
  })

  test('streak badge appears after consecutive correct answers', async ({ page }) => {
    await page.goto('/')

    // Complete 3 consecutive correct turns
    for (let i = 0; i < 3; i++) {
      await page.evaluate(() => {
        ;(window as any).__mockCorrectAnswer__()
      })
      await page.waitForTimeout(1000)
    }

    // Streak badge should appear
    const streakBadge = await page.getByTestId('streak-badge')
    await expect(streakBadge).toBeVisible()
  })

  test('grammar error triggers coach correction', async ({ page }) => {
    await page.goto('/')

    // Input sentence with grammar error
    await page.evaluate(() => {
      ;(window as any).__mockTextInput__('I goed to the store yesterday')
    })

    await page.waitForTimeout(2000)

    // Spirit coach should provide correction
    const coachCorrection = await page.getByTestId('coach-correction')
    await expect(coachCorrection).toBeVisible()
    expect(await coachCorrection.textContent()).toContain('went')
  })

  test('reward panel shows collected badges', async ({ page }) => {
    await page.goto('/')

    // Open rewards panel
    await page.getByTestId('open-rewards').click()

    // Badge collection should be visible
    const badgeList = page.getByTestId('badge-item')
    await expect(badgeList.first()).toBeVisible()

    // LXP progress bar should show
    const lxpBar = page.getByTestId('lxp-progress-bar')
    await expect(lxpBar).toBeVisible()
  })
})
