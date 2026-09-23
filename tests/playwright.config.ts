import { defineConfig, devices } from '@playwright/test'

// 部署环境（docker-compose）：parent-dashboard 宿主 3333、auth-service 宿主 8310。
// 测试已运行容器时设 NO_WEBSERVER=1 跳过自启 webserver。
const BASE_URL = process.env.BASE_URL || 'http://localhost:3333'
const API_URL = process.env.API_URL || 'http://localhost:8310'

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
      url: 'http://localhost:3333',
      reuseExistingServer: true,
      timeout: 60000,
    },
  ],
})
