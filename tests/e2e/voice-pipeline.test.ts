import { test, expect } from './fixtures'

test.describe('Voice Pipeline E2E', () => {
  test('complete turn: player speaks → ASR → NPC responds → TTS plays', async ({ page }) => {
    await page.goto('/')

    // Mock microphone input (use synthetic audio)
    await page.evaluate(async () => {
      // Simulate VAD detecting speech
      ;(window as any).__mockAudioInput__ = 'generateTestSpeech'
    })

    // Wait for NPC response bubble
    await page.waitForSelector('[data-testid="npc-speech-bubble"]', { timeout: 5000 })

    const npcText = await page.getByTestId('npc-speech-bubble').textContent()
    expect(npcText).toBeTruthy()
    expect(npcText!.length).toBeGreaterThan(0)

    // Verify LXP was awarded
    const lxpDisplay = await page.getByTestId('lxp-earned')
    expect(lxpDisplay).toBeVisible()
  })

  test('wake word triggers spirit coach', async ({ page }) => {
    await page.goto('/')

    // Simulate wake word
    await page.evaluate(() => {
      ;(window as any).__mockWakeWord__('小灵')
    })

    // Spirit coach should appear within 500ms
    const coachVisible = await page.waitForSelector('[data-testid="spirit-coach"]', { timeout: 500 })
    expect(coachVisible).toBeTruthy()
  })

  test('5 second silence triggers coach hint', async ({ page }) => {
    await page.goto('/')

    // Start dialogue
    await page.getByTestId('start-dialogue').click()

    // Wait 5+ seconds without speaking
    await page.waitForTimeout(5500)

    // Coach hint should appear
    const hintVisible = await page.getByTestId('coach-hint')
    expect(hintVisible).toBeVisible()
  })

  test('error handling: API failure shows fallback', async ({ page }) => {
    // Mock failed API response
    await page.route('**/api/v1/dialogue', async (route) => {
      await route.fulfill({
        status: 500,
        contentType: 'application/json',
        body: JSON.stringify({ error: 'Service unavailable' }),
      })
    })

    await page.goto('/')

    // Trigger dialogue
    await page.getByTestId('start-dialogue').click()
    await page.waitForTimeout(3000)

    // Fallback message should display
    const fallback = await page.getByTestId('fallback-message')
    expect(fallback).toBeVisible()
  })
})
