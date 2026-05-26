import { beforeEach, describe, expect, it } from 'vitest'
import { InterventionPolicy } from '../services/intervention-policy.js'

// Mock Redis: with get/set methods and controllable state
function createMockRedis(initialValues: Record<string, string> = {}) {
  const store = new Map(Object.entries(initialValues))

  return {
    async get(key: string): Promise<string | null> {
      return store.get(key) ?? null
    },
    async set(key: string, value: string, _mode?: string, _ttl?: number): Promise<string> {
      store.set(key, value)
      return 'OK'
    },
    // Expose internal store for assertions
    _store: store,
  }
}

describe('InterventionPolicy', () => {
  it('wake trigger → shouldIntervene always returns true, markIntervened does not set cooldown', async () => {
    const redis = createMockRedis()
    const policy = new InterventionPolicy(redis as never)

    // shouldIntervene always true for wake
    const allowed = await policy.shouldIntervene({ trigger: 'wake', userId: 'user-1' })
    expect(allowed).toBe(true)

    // markIntervened does nothing for wake (no key set)
    await policy.markIntervened({ trigger: 'wake', userId: 'user-1' })
    expect(redis._store.size).toBe(0) // no cooldown key stored

    // shouldIntervene still true after "markIntervened" for wake
    const allowedAgain = await policy.shouldIntervene({ trigger: 'wake', userId: 'user-1' })
    expect(allowedAgain).toBe(true)
  })

  it('error trigger (no cooldown) → shouldIntervene returns true, markIntervened sets 20s cooldown', async () => {
    const redis = createMockRedis()
    const policy = new InterventionPolicy(redis as never)

    // No cooldown → allowed
    const allowed = await policy.shouldIntervene({ trigger: 'error', userId: 'user-1' })
    expect(allowed).toBe(true)

    // markIntervened sets the cooldown key
    await policy.markIntervened({ trigger: 'error', userId: 'user-1' })
    expect(redis._store.has('cooldown:user-1:spirit:error')).toBe(true)
    expect(redis._store.get('cooldown:user-1:spirit:error')).toBe('1')
  })

  it('error trigger (during cooldown) → redis.get returns non-null → shouldIntervene returns false', async () => {
    // Pre-set the cooldown key to simulate active cooldown
    const redis = createMockRedis({ 'cooldown:user-1:spirit:error': '1' })
    const policy = new InterventionPolicy(redis as never)

    const allowed = await policy.shouldIntervene({ trigger: 'error', userId: 'user-1' })
    expect(allowed).toBe(false)
  })

  it('silence trigger (no cooldown) → shouldIntervene returns true, markIntervened sets 30s cooldown', async () => {
    const redis = createMockRedis()
    const policy = new InterventionPolicy(redis as never)

    // No cooldown → allowed
    const allowed = await policy.shouldIntervene({ trigger: 'silence', userId: 'user-1' })
    expect(allowed).toBe(true)

    // markIntervened sets the cooldown key
    await policy.markIntervened({ trigger: 'silence', userId: 'user-1' })
    expect(redis._store.has('cooldown:user-1:spirit:silence')).toBe(true)
    expect(redis._store.get('cooldown:user-1:spirit:silence')).toBe('1')
  })

  it('silence trigger (during cooldown) → redis.get returns non-null → shouldIntervene returns false', async () => {
    // Pre-set the cooldown key to simulate active cooldown
    const redis = createMockRedis({ 'cooldown:user-1:spirit:silence': '1' })
    const policy = new InterventionPolicy(redis as never)

    const allowed = await policy.shouldIntervene({ trigger: 'silence', userId: 'user-1' })
    expect(allowed).toBe(false)
  })

  it('redis.get throws exception → shouldIntervene returns false (fail-safe)', async () => {
    const brokenRedis = {
      async get(_key: string): Promise<string | null> {
        throw new Error('redis connection lost')
      },
      async set(_key: string, _value: string, _mode?: string, _ttl?: number): Promise<string> {
        return 'OK'
      },
    }
    const policy = new InterventionPolicy(brokenRedis as never)

    const allowed = await policy.shouldIntervene({ trigger: 'error', userId: 'user-1' })
    expect(allowed).toBe(false)
  })

  it('each user has independent cooldown keys', async () => {
    const redis = createMockRedis()
    const policy = new InterventionPolicy(redis as never)

    // Mark user-1 as having error intervention
    await policy.markIntervened({ trigger: 'error', userId: 'user-1' })

    // user-1 should be blocked
    const user1Allowed = await policy.shouldIntervene({ trigger: 'error', userId: 'user-1' })
    expect(user1Allowed).toBe(false)

    // user-2 should still be allowed (different key)
    const user2Allowed = await policy.shouldIntervene({ trigger: 'error', userId: 'user-2' })
    expect(user2Allowed).toBe(true)
  })
})
