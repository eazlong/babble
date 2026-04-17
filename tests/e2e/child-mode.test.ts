import { test, expect } from './fixtures'

test.describe('Child Mode E2E', () => {
  test('child mode restricts session time', async ({ page }) => {
    await page.goto('/')

    // Verify child mode is active
    const childModeIndicator = page.getByTestId('child-mode-active')
    await expect(childModeIndicator).toBeVisible()

    // Mock time advancement to near limit
    await page.evaluate(() => {
      ;(window as any).__mockTimeRemaining__(60) // 60 seconds left
    })

    // Warning should appear when approaching limit
    await expect(page.getByTestId('time-warning')).toBeVisible()

    // Wait for time to expire
    await page.waitForTimeout(65000)

    // Session should end and redirect to summary
    await expect(page.getByTestId('session-summary')).toBeVisible()
  })

  test('content filter blocks inappropriate text', async ({ page }) => {
    await page.goto('/')

    // Start dialogue with filtered content
    await page.getByTestId('start-dialogue').click()

    // Mock input that should be filtered
    await page.evaluate(() => {
      ;(window as any).__mockTextInput__('[FILTERED_CONTENT]')
    })

    // Content filter should block it
    await expect(page.getByTestId('content-blocked')).toBeVisible()
  })

  test('parent dashboard shows child activity', async ({ page, apiToken }) => {
    // Navigate to parent dashboard
    await page.goto('/dashboard')

    // Login as parent
    await page.getByTestId('parent-login').click()
    await expect(page.getByTestId('dashboard-header')).toBeVisible()

    // Should see child's recent sessions
    const sessionItems = page.getByTestId('child-session-item')
    expect(await sessionItems.count()).toBeGreaterThan(0)

    // Should see progress chart
    await expect(page.getByTestId('progress-chart')).toBeVisible()

    // Should see vocabulary count
    const vocabCount = await page.getByTestId('vocabulary-count').textContent()
    expect(Number(vocabCount)).toBeGreaterThan(0)
  })

  test('parent can adjust time limit', async ({ page }) => {
    await page.goto('/settings')

    // Find time limit control
    const timeSlider = page.getByTestId('time-limit-slider')
    await expect(timeSlider).toBeVisible()

    // Adjust time limit
    await timeSlider.fill('45')

    // Save settings
    await page.getByTestId('save-settings').click()

    // Confirmation should appear
    await expect(page.getByTestId('settings-saved')).toBeVisible()
  })
})
