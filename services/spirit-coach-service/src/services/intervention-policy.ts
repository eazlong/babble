const cooldownSeconds = {
  error: 20,
  silence: 30,
} as const

export class InterventionPolicy {
  constructor(private readonly redis: {
    get(key: string): Promise<string | null>
    set(key: string, value: string, mode?: string, ttlKey?: string, ttl?: number): Promise<unknown>
  }) {}

  async shouldIntervene({ trigger, userId }: { trigger: 'wake' | 'error' | 'silence'; userId: string }) {
    if (trigger === 'wake') {
      return true
    }

    try {
      const value = await this.redis.get(this.cooldownKey(trigger, userId))
      return value === null
    } catch {
      return false
    }
  }

  async markIntervened({ trigger, userId }: { trigger: 'wake' | 'error' | 'silence'; userId: string }) {
    if (trigger === 'wake') {
      return
    }

    await this.redis.set(
      this.cooldownKey(trigger, userId),
      '1',
      'EX',
      cooldownSeconds[trigger],
    )
  }

  private cooldownKey(trigger: 'error' | 'silence', userId: string) {
    return `cooldown:${userId}:spirit:${trigger}`
  }
}
