/**
 * StreakTracker — tracks consecutive error / correct streaks per user.
 *
 * Extracted from ErrorDetector so it can be used by CoachInputConsumer
 * independently of the error detection logic. The LLM coach reads the
 * streak counts via prompt injection to adapt its tone.
 */

interface UserStreak {
  errorStreak: number
  correctStreak: number
}

export class StreakTracker {
  private readonly userStreaks: Map<string, UserStreak> = new Map()

  recordError(userId: string): void {
    const streak = this.getOrCreate(userId)
    streak.errorStreak += 1
    streak.correctStreak = 0
  }

  recordCorrect(userId: string): void {
    const streak = this.getOrCreate(userId)
    streak.correctStreak += 1
    streak.errorStreak = 0
  }

  getErrorStreak(userId: string): number {
    return this.getOrCreate(userId).errorStreak
  }

  getCorrectStreak(userId: string): number {
    return this.getOrCreate(userId).correctStreak
  }

  shouldReduceDifficulty(userId: string, threshold: number = 3): boolean {
    return this.getErrorStreak(userId) >= threshold
  }

  checkStreakReward(userId: string, threshold: number = 3): boolean {
    return this.getCorrectStreak(userId) >= threshold
  }

  clearStreak(userId: string): void {
    const streak = this.getOrCreate(userId)
    streak.errorStreak = 0
    streak.correctStreak = 0
  }

  /** Reset everything (useful in tests) */
  clearAll(): void {
    this.userStreaks.clear()
  }

  private getOrCreate(userId: string): UserStreak {
    let streak = this.userStreaks.get(userId)
    if (!streak) {
      streak = { errorStreak: 0, correctStreak: 0 }
      this.userStreaks.set(userId, streak)
    }
    return streak
  }
}
