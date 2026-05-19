import { beforeEach, describe, expect, it } from 'vitest'
import { InterventionPolicy } from '../services/intervention-policy.js'

class FakeRedis {
  private values = new Map<string, string>()

  async get(key: string) {
    return this.values.get(key) ?? null
  }

  async set(key: string, value: string, _mode?: string, _ttlKey?: string, _ttl?: number) {
    this.values.set(key, value)
    return 'OK'
  }
}

describe('InterventionPolicy', () => {
  let redis: FakeRedis
  let policy: InterventionPolicy

  beforeEach(() => {
    redis = new FakeRedis()
    policy = new InterventionPolicy(redis as never)
  })

  it('always allows wake triggers', async () => {
    await expect(policy.shouldIntervene({ trigger: 'wake', userId: 'user-1' })).resolves.toBe(true)
  })

  it('blocks error triggers during cooldown', async () => {
    await policy.markIntervened({ trigger: 'error', userId: 'user-1' })
    await expect(policy.shouldIntervene({ trigger: 'error', userId: 'user-1' })).resolves.toBe(false)
  })

  it('blocks silence triggers during cooldown', async () => {
    await policy.markIntervened({ trigger: 'silence', userId: 'user-1' })
    await expect(policy.shouldIntervene({ trigger: 'silence', userId: 'user-1' })).resolves.toBe(false)
  })

  it('fails closed when redis throws for cooldown checks', async () => {
    const brokenPolicy = new InterventionPolicy({
      async get() {
        throw new Error('redis down')
      },
      async set() {
        throw new Error('redis down')
      },
    } as never)

    await expect(brokenPolicy.shouldIntervene({ trigger: 'error', userId: 'user-1' })).resolves.toBe(false)
  })
})
