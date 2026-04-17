import { test, expect } from './fixtures'

test.describe('Quest Flow E2E', () => {
  test('accept and complete a main quest', async ({ page }) => {
    await page.goto('/')

    // Enter marketplace scene
    await page.getByText('王都集市').click()

    // Accept quest from NPC
    await page.getByTestId('npc-merchant').click()
    await page.getByTestId('accept-quest').click()

    // Verify quest objective appears
    await expect(page.getByTestId('quest-objective')).toBeVisible()

    // Simulate completing dialogue turns
    for (let i = 0; i < 3; i++) {
      await page.evaluate(() => {
        ;(window as any).__mockCompleteTurn__()
      })
      await page.waitForTimeout(1000)
    }

    // Quest should be marked complete
    await expect(page.getByTestId('quest-complete')).toBeVisible()

    // Radar chart should appear for assessment
    await expect(page.getByTestId('assessment-radar')).toBeVisible()
  })

  test('daily quests reset and appear', async ({ page }) => {
    await page.goto('/')

    // Open quest panel
    await page.getByTestId('open-quests').click()

    // Should see 3 daily quests
    const dailyQuests = page.getByTestId('daily-quest-item')
    await expect(dailyQuests).toHaveCount(3)
  })

  test('quest progress persists after refresh', async ({ page }) => {
    await page.goto('/')

    // Accept a quest
    await page.getByTestId('npc-merchant').click()
    await page.getByTestId('accept-quest').click()
    await expect(page.getByTestId('quest-objective')).toBeVisible()

    // Complete one turn
    await page.evaluate(() => {
      ;(window as any).__mockCompleteTurn__()
    })
    await page.waitForTimeout(1000)

    // Refresh page
    await page.reload()

    // Quest should still be visible and in progress
    await expect(page.getByTestId('quest-objective')).toBeVisible()
    const progress = await page.getByTestId('quest-progress').textContent()
    expect(progress).toContain('1/')
  })
})
