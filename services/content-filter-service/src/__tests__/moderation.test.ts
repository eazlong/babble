import { test, expect } from 'vitest'
import { ContentFilter } from '../services/moderation'

test('safe text passes in child mode', async () => {
  const filter = new ContentFilter()
  const result = await filter.check('Hello, how are you?', true)
  expect(result.safe).toBe(true)
  expect(result.flagged_categories).toEqual([])
})

test('unsafe text is flagged in child mode', async () => {
  const filter = new ContentFilter()
  const result = await filter.check('I want to kill time', true)
  expect(result.safe).toBe(false)
  expect(result.flagged_categories).toContain('child_unsafe')
})

test('child mode disabled - no filtering', async () => {
  const filter = new ContentFilter()
  const result = await filter.check('I want to kill time', false)
  expect(result.safe).toBe(true)
})
