export class TimeManager {
  private dailyLimitMinutes: number
  private usedToday: number = 0
  private sessionStart: number = 0
  private timerInterval: ReturnType<typeof setInterval> | null = null

  onTimeUp: (() => void) | null = null
  onWarning: ((minutesLeft: number) => void) | null = null

  constructor(dailyLimitMinutes: number) {
    this.dailyLimitMinutes = dailyLimitMinutes
    this.startTimer()
  }

  private startTimer(): void {
    this.sessionStart = Date.now()

    this.timerInterval = setInterval(() => {
      const sessionMinutes = (Date.now() - this.sessionStart) / 60000
      const totalUsed = this.usedToday + sessionMinutes

      if (totalUsed >= this.dailyLimitMinutes) {
        this.onTimeUp?.()
        this.stopTimer()
      } else if (totalUsed >= this.dailyLimitMinutes - 5) {
        const minutesLeft = this.dailyLimitMinutes - totalUsed
        this.onWarning?.(Math.ceil(minutesLeft))
      }
    }, 30000)
  }

  stopTimer(): void {
    if (this.timerInterval) {
      clearInterval(this.timerInterval)
      this.timerInterval = null
    }
    this.usedToday += (Date.now() - this.sessionStart) / 60000
  }

  getRemainingMinutes(): number {
    const sessionMinutes = (Date.now() - this.sessionStart) / 60000
    return Math.max(0, this.dailyLimitMinutes - this.usedToday - sessionMinutes)
  }
}
