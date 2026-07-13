import { describe, expect, it, beforeEach } from 'vitest'
import { StreakTracker } from '../services/streak-tracker.js'

describe('StreakTracker', () => {
  let tracker: StreakTracker

  beforeEach(() => {
    tracker = new StreakTracker()
  })

  describe('error streak', () => {
    it('starts at zero for a new user', () => {
      expect(tracker.getErrorStreak('user-1')).toBe(0)
    })

    it('increments on each recordError', () => {
      tracker.recordError('user-1')
      expect(tracker.getErrorStreak('user-1')).toBe(1)
      tracker.recordError('user-1')
      expect(tracker.getErrorStreak('user-1')).toBe(2)
      tracker.recordError('user-1')
      expect(tracker.getErrorStreak('user-1')).toBe(3)
    })

    it('resets correct streak when recording error', () => {
      tracker.recordCorrect('user-1')
      tracker.recordCorrect('user-1')
      expect(tracker.getCorrectStreak('user-1')).toBe(2)

      tracker.recordError('user-1')
      expect(tracker.getCorrectStreak('user-1')).toBe(0)
      expect(tracker.getErrorStreak('user-1')).toBe(1)
    })
  })

  describe('correct streak', () => {
    it('starts at zero for a new user', () => {
      expect(tracker.getCorrectStreak('user-1')).toBe(0)
    })

    it('increments on each recordCorrect', () => {
      tracker.recordCorrect('user-1')
      expect(tracker.getCorrectStreak('user-1')).toBe(1)
      tracker.recordCorrect('user-1')
      expect(tracker.getCorrectStreak('user-1')).toBe(2)
    })

    it('resets error streak when recording correct', () => {
      tracker.recordError('user-1')
      tracker.recordError('user-1')
      expect(tracker.getErrorStreak('user-1')).toBe(2)

      tracker.recordCorrect('user-1')
      expect(tracker.getErrorStreak('user-1')).toBe(0)
      expect(tracker.getCorrectStreak('user-1')).toBe(1)
    })
  })

  describe('thresholds', () => {
    it('shouldReduceDifficulty defaults to threshold 3', () => {
      tracker.recordError('user-1')
      tracker.recordError('user-1')
      expect(tracker.shouldReduceDifficulty('user-1')).toBe(false)

      tracker.recordError('user-1')
      expect(tracker.shouldReduceDifficulty('user-1')).toBe(true)
    })

    it('shouldReduceDifficulty accepts custom threshold', () => {
      tracker.recordError('user-1')
      expect(tracker.shouldReduceDifficulty('user-1', 1)).toBe(true)
      expect(tracker.shouldReduceDifficulty('user-1', 5)).toBe(false)
    })

    it('checkStreakReward defaults to threshold 3', () => {
      tracker.recordCorrect('user-1')
      tracker.recordCorrect('user-1')
      expect(tracker.checkStreakReward('user-1')).toBe(false)

      tracker.recordCorrect('user-1')
      expect(tracker.checkStreakReward('user-1')).toBe(true)
    })
  })

  describe('clearStreak', () => {
    it('resets both streaks for a user', () => {
      tracker.recordError('user-1')
      tracker.recordError('user-1')
      tracker.recordCorrect('user-1')
      tracker.recordCorrect('user-1')

      tracker.clearStreak('user-1')
      expect(tracker.getErrorStreak('user-1')).toBe(0)
      expect(tracker.getCorrectStreak('user-1')).toBe(0)
    })
  })

  describe('user isolation', () => {
    it('tracks different users independently', () => {
      tracker.recordError('user-a')
      tracker.recordError('user-a')
      tracker.recordCorrect('user-b')

      expect(tracker.getErrorStreak('user-a')).toBe(2)
      expect(tracker.getErrorStreak('user-b')).toBe(0)
      expect(tracker.getCorrectStreak('user-a')).toBe(0)
      expect(tracker.getCorrectStreak('user-b')).toBe(1)
    })
  })

  describe('clearAll', () => {
    it('resets all users', () => {
      tracker.recordError('user-a')
      tracker.recordCorrect('user-b')
      tracker.clearAll()
      expect(tracker.getErrorStreak('user-a')).toBe(0)
      expect(tracker.getCorrectStreak('user-b')).toBe(0)
    })
  })
})
