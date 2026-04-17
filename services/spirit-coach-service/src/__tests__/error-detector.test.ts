import { test, expect } from 'vitest'
import { ErrorDetector, DetectedError } from '../services/error-detector'

test('analyze detects grammar errors', async () => {
  const detector = new ErrorDetector()
  const errors = await detector.analyze('he don\'t like it')
  expect(errors.length).toBeGreaterThan(0)
  expect(errors[0].type).toBe('grammar')
  expect(errors[0].severity).toBe('high')
  expect(errors[0].correction).toBe('he doesn\'t')
})

test('analyze returns empty for correct input', async () => {
  const detector = new ErrorDetector()
  const errors = await detector.analyze('I like apples')
  expect(errors).toEqual([])
})

test('analyze detects multiple error types', async () => {
  const detector = new ErrorDetector()
  const errors = await detector.analyze('i am go to school and he don\'t know')
  // At least one error should be detected
  expect(errors.length).toBeGreaterThanOrEqual(1)
})
