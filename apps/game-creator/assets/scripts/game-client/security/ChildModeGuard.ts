import { http } from '../network/HttpClient'
import { TimeManager } from './TimeManager'

export class ChildModeGuard {
  private isChildModeFlag: boolean = false
  private timeManager: TimeManager | null = null
  private dailyLimitMinutes: number = 60

  async initialize(userId: string, accountType: string): Promise<void> {
    this.isChildModeFlag = accountType === 'child'

    if (this.isChildModeFlag) {
      const { data: childAccount } = await http.get<{ daily_time_limit_minutes?: number }>(`/child-accounts/${userId}`)
      if (childAccount) {
        this.dailyLimitMinutes = childAccount.daily_time_limit_minutes ?? 60
      }

      this.timeManager = new TimeManager(this.dailyLimitMinutes)
      this.timeManager.onTimeUp = () => this.handleTimeUp()

      this.blockSocialFeatures()
    }
  }

  isChildMode(): boolean {
    return this.isChildModeFlag
  }

  private blockSocialFeatures(): void {
    // Disable: friend requests, public leaderboards, UGC, chat with other players
    // These are server-enforced, but client also hides UI
  }

  handleTimeUp(): void {
    if (this.isChildModeFlag) {
      http.post('/sessions/end', { reason: 'time_limit' })
    }
  }

  async handleVoiceExit(): Promise<void> {
    if (this.isChildModeFlag) {
      await http.post('/sessions/end', { reason: 'voice_exit' })
    }
  }

  canAccessFeature(feature: string): boolean {
    if (!this.isChildModeFlag) return true

    const blockedForChild = ['social', 'sharing', 'leaderboard_public', 'user_generated_content']
    return !blockedForChild.includes(feature)
  }
}
