import { test, expect, vi, beforeEach, afterEach, describe } from 'vitest'
import { TimeManager } from '../TimeManager'

// Mock Date.now for deterministic testing
beforeEach(() => {
  vi.useFakeTimers()
  vi.setSystemTime(new Date('2026-04-17T10:00:00.000Z'))
})

afterEach(() => {
  vi.restoreAllMocks()
  vi.useRealTimers()
})

describe('TimeManager', () => {
  test('initializes with given daily limit', () => {
    const tm = new TimeManager(60)
    expect(tm.getRemainingMinutes()).toBe(60)
  })

  test('starts timer on construction', () => {
    const onTimeUp = vi.fn()
    const tm = new TimeManager(1)
    tm.onTimeUp = onTimeUp

    // Advance time by 1 minute (the limit)
    vi.advanceTimersByTime(60000)

    expect(onTimeUp).toHaveBeenCalled()
  })

  test('fires warning 5 minutes before time is up', () => {
    const onWarning = vi.fn()
    const tm = new TimeManager(10)
    tm.onWarning = onWarning

    // Advance to 6 minutes (4 minutes remaining - should trigger warning)
    vi.advanceTimersByTime(6 * 60000)

    // Warning fires when totalUsed >= limit - 5, so at that point
    // minutesLeft = limit - totalUsed <= 5
    expect(onWarning).toHaveBeenCalled()
    expect(onWarning.mock.calls[0][0]).toBeLessThanOrEqual(5)
  })

  test('stops timer when stopTimer is called', () => {
    const onTimeUp = vi.fn()
    const tm = new TimeManager(1)
    tm.onTimeUp = onTimeUp
    tm.stopTimer()

    // Advance past the limit
    vi.advanceTimersByTime(120000)

    expect(onTimeUp).not.toHaveBeenCalled()
  })

  test('getRemainingMinutes returns correct value after session time', () => {
    const tm = new TimeManager(60)

    // Advance 15 minutes
    vi.advanceTimersByTime(15 * 60000)

    const remaining = tm.getRemainingMinutes()
    expect(remaining).toBeCloseTo(45, 0)
  })

  test('getRemainingMinutes returns 0 when time is exceeded', () => {
    const tm = new TimeManager(5)

    // Advance 10 minutes
    vi.advanceTimersByTime(10 * 60000)

    expect(tm.getRemainingMinutes()).toBe(0)
  })

  test('checks timer every 30 seconds', () => {
    const onTimeUp = vi.fn()
    const tm = new TimeManager(1)
    tm.onTimeUp = onTimeUp

    // At 30 seconds, should not fire yet
    vi.advanceTimersByTime(30000)
    expect(onTimeUp).not.toHaveBeenCalled()

    // At 60 seconds (the limit), should fire
    vi.advanceTimersByTime(30000)
    expect(onTimeUp).toHaveBeenCalled()
  })
})
