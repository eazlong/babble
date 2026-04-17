import { test, expect, vi, beforeEach, describe } from 'vitest'
import { ChildModeGuard } from '../ChildModeGuard'
import { http } from '../../network/HttpClient'

// Mock http
vi.mock('../../network/HttpClient', () => ({
  http: {
    get: vi.fn(),
    post: vi.fn()
  }
}))

describe('ChildModeGuard', () => {
  beforeEach(() => {
    vi.clearAllMocks()
    vi.mocked(http.get).mockResolvedValue({ data: null })
  })

  test('initializes child mode for child account type', async () => {
    const guard = new ChildModeGuard()
    await guard.initialize('child-123', 'child')

    expect(guard.isChildMode()).toBe(true)
  })

  test('does not enable child mode for adult account type', async () => {
    const guard = new ChildModeGuard()
    await guard.initialize('adult-123', 'adult')

    expect(guard.isChildMode()).toBe(false)
  })

  test('fetches child account settings when child mode is enabled', async () => {
    vi.mocked(http.get).mockResolvedValue({
      data: { daily_time_limit_minutes: 45 }
    })

    const guard = new ChildModeGuard()
    await guard.initialize('child-123', 'child')

    expect(http.get).toHaveBeenCalledWith('/child-accounts/child-123')
  })

  test('uses default time limit when no settings returned', async () => {
    vi.mocked(http.get).mockResolvedValue({ data: null })

    const guard = new ChildModeGuard()
    await guard.initialize('child-123', 'child')

    expect(guard.isChildMode()).toBe(true)
  })

  test('blocks social features for child accounts', async () => {
    const guard = new ChildModeGuard()
    await guard.initialize('child-123', 'child')

    expect(guard.canAccessFeature('social')).toBe(false)
    expect(guard.canAccessFeature('sharing')).toBe(false)
    expect(guard.canAccessFeature('leaderboard_public')).toBe(false)
    expect(guard.canAccessFeature('user_generated_content')).toBe(false)
  })

  test('allows all features for adult accounts', async () => {
    const guard = new ChildModeGuard()
    await guard.initialize('adult-123', 'adult')

    expect(guard.canAccessFeature('social')).toBe(true)
    expect(guard.canAccessFeature('sharing')).toBe(true)
    expect(guard.canAccessFeature('leaderboard_public')).toBe(true)
  })

  test('handles voice exit by ending session', async () => {
    const guard = new ChildModeGuard()
    await guard.initialize('child-123', 'child')

    await guard.handleVoiceExit()

    expect(http.post).toHaveBeenCalledWith('/sessions/end', { reason: 'voice_exit' })
  })

  test('voice exit is no-op for adult accounts', async () => {
    const guard = new ChildModeGuard()
    await guard.initialize('adult-123', 'adult')

    await guard.handleVoiceExit()

    expect(http.post).not.toHaveBeenCalled()
  })

  test('handles time up by ending session with time_limit reason', async () => {
    const guard = new ChildModeGuard()
    await guard.initialize('child-123', 'child')

    // Trigger time up manually since we can't wait for real timer
    ;(guard as any).handleTimeUp()

    expect(http.post).toHaveBeenCalledWith('/sessions/end', { reason: 'time_limit' })
  })
})
