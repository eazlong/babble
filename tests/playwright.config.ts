import { defineConfig, devices } from '@playwright/test'

const BASE_URL = process.env.BASE_URL || 'http://localhost:3300'
const API_URL = process.env.API_URL || 'http://localhost:8302'

export default defineConfig({
  testDir: './e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: [
    ['html', { outputFolder: 'e2e-report' }],
    ['list']
  ],
  use: {
    baseURL: BASE_URL,
    trace: 'on-first-retry',
    video: 'retain-on-failure',
    screenshot: 'only-on-failure',
  },
  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'Mobile Safari',
      use: { ...devices['iPhone 14'] },
    },
  ],
  webServer: process.env.NO_WEBSERVER ? undefined : [
    {
      command: 'cd .. && pnpm --filter @linguaquest/parent-dashboard dev',
      url: 'http://localhost:3300',
      reuseExistingServer: true,
      timeout: 60000,
    },
  ],
})
