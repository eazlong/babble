import { test as base, expect } from '@playwright/test'

export interface TestFixtures {
  apiToken: string
  testSessionId: string
  testUserId: string
}

export const test = base.extend<TestFixtures>({
  apiToken: async ({}, use) => {
    const token = process.env.TEST_API_TOKEN || 'dev-token'
    await use(token)
  },
  testSessionId: async ({}, use) => {
    const sessionId = `test-session-${Date.now()}`
    await use(sessionId)
  },
  testUserId: async ({}, use) => {
    const userId = process.env.TEST_USER_ID || 'test-user-001'
    await use(userId)
  },
})

export { expect }
