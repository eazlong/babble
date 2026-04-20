import { describe, it, expect, beforeEach } from 'vitest'
import { ErrorDetector } from './error-detector.js'

describe('ErrorDetector', () => {
  let detector: ErrorDetector

  beforeEach(() => {
    detector = new ErrorDetector()
  })

  // ============================================================
  // Existing analyze method (preserved)
  // ============================================================

  describe('analyze', () => {
    it('should detect "I am go" grammar error', async () => {
      const errors = await detector.analyze('I am go to school')
      expect(errors).toHaveLength(1)
      expect(errors[0].type).toBe('grammar')
      expect(errors[0].severity).toBe('high')
      expect(errors[0].correction).toBe('I go / I am going')
    })

    it('should detect "he don\'t" grammar error', async () => {
      const errors = await detector.analyze("He don't like it")
      expect(errors).toHaveLength(1)
      expect(errors[0].type).toBe('grammar')
      expect(errors[0].correction).toBe("he doesn't")
    })

    it('should detect both errors when both patterns present', async () => {
      const errors = await detector.analyze("I am go and he don't care")
      expect(errors).toHaveLength(2)
    })

    it('should return empty array for correct input', async () => {
      const errors = await detector.analyze('I go to school. He doesn\'t like it.')
      expect(errors).toHaveLength(0)
    })

    it('should default to A1 level', async () => {
      const errors = await detector.analyze('I am go')
      expect(errors).toHaveLength(1)
    })
  })

  // ============================================================
  // 1. Curriculum Vocabulary Matching
  // ============================================================

  describe('checkCurriculumVocabulary', () => {
    it('should detect animal vocabulary', () => {
      const result = detector.checkCurriculumVocabulary('I see a cat and a dog')
      expect(result.hasCurriculumVocab).toBe(true)
      expect(result.matchedWords).toContain('cat')
      expect(result.matchedWords).toContain('dog')
      expect(result.matchedCategories).toContain('animals')
      expect(result.matchedCategoriesCn).toContain('动物')
    })

    it('should detect number vocabulary', () => {
      const result = detector.checkCurriculumVocabulary('I have three apple')
      expect(result.hasCurriculumVocab).toBe(true)
      expect(result.matchedWords).toContain('three')
      expect(result.matchedWords).toContain('apple')
      expect(result.matchedCategories).toContain('numbers')
      expect(result.matchedCategories).toContain('food_and_drink')
    })

    it('should detect color vocabulary', () => {
      const result = detector.checkCurriculumVocabulary('The sky is blue')
      expect(result.hasCurriculumVocab).toBe(true)
      expect(result.matchedWords).toContain('blue')
      expect(result.matchedCategories).toContain('colors')
    })

    it('should detect family vocabulary', () => {
      const result = detector.checkCurriculumVocabulary('My mother is a teacher')
      expect(result.hasCurriculumVocab).toBe(true)
      expect(result.matchedWords).toContain('mother')
      expect(result.matchedWords).toContain('teacher')
      expect(result.matchedCategories).toContain('family')
      expect(result.matchedCategories).toContain('school')
    })

    it('should detect multiple categories in one sentence', () => {
      const result = detector.checkCurriculumVocabulary(
        'My happy mother eats a red apple'
      )
      expect(result.matchedCategories).toContain('family')
      expect(result.matchedCategories).toContain('emotions_and_feelings')
      expect(result.matchedCategories).toContain('colors')
      expect(result.matchedCategories).toContain('food_and_drink')
    })

    it('should return no matches for non-curriculum words', () => {
      const result = detector.checkCurriculumVocabulary('The xylophone zephyrs')
      expect(result.hasCurriculumVocab).toBe(false)
      expect(result.matchedWords).toHaveLength(0)
      expect(result.coverageScore).toBe(0)
    })

    it('should handle empty input', () => {
      const result = detector.checkCurriculumVocabulary('')
      expect(result.hasCurriculumVocab).toBe(false)
      expect(result.coverageScore).toBe(0)
    })

    it('should calculate coverage score correctly', () => {
      // 'cat dog xyz' -> 2/3 curriculum words
      const result = detector.checkCurriculumVocabulary('cat dog xyz')
      expect(result.coverageScore).toBeCloseTo(2 / 3, 2)
    })

    it('should be case-insensitive', () => {
      const result1 = detector.checkCurriculumVocabulary('I like CATS')
      const result2 = detector.checkCurriculumVocabulary('I like cats')
      expect(result1.matchedWords).toEqual(result2.matchedWords)
    })

    it('should detect pronouns and basic verbs', () => {
      const result = detector.checkCurriculumVocabulary('I can run fast')
      expect(result.hasCurriculumVocab).toBe(true)
      expect(result.matchedWords).toContain('i')
      expect(result.matchedWords).toContain('can')
      expect(result.matchedWords).toContain('run')
    })
  })

  // ============================================================
  // 2. Silent Timeout Hints
  // ============================================================

  describe('generateSilentHint', () => {
    it('should generate hint for animals category', () => {
      const hint = detector.generateSilentHint('animals')
      expect(hint.hintEn).toBeTruthy()
      expect(hint.hintCn).toBeTruthy()
      expect(hint.category).toBe('动物')
      expect(hint.hintEn.toLowerCase()).toContain('animal')
    })

    it('should generate hint for numbers category', () => {
      const hint = detector.generateSilentHint('numbers')
      expect(hint.category).toBe('数字')
      expect(hint.hintEn).toContain('count')
    })

    it('should generate hint for colors category', () => {
      const hint = detector.generateSilentHint('colors')
      expect(hint.category).toBe('颜色')
      expect(hint.hintEn.toLowerCase()).toContain('color')
    })

    it('should generate hint for food_and_drink category', () => {
      const hint = detector.generateSilentHint('food_and_drink')
      expect(hint.category).toBe('食物与饮料')
      expect(hint.hintCn).toContain('吃')
    })

    it('should return fallback hint for unknown category', () => {
      const hint = detector.generateSilentHint('unknown_category')
      expect(hint.hintEn).toBeTruthy()
      expect(hint.hintCn).toBeTruthy()
      expect(hint.category).toBe('通用')
    })

    it('should generate hint for greetings category', () => {
      const hint = detector.generateSilentHint('greetings_and_farewells')
      expect(hint.category).toBe('问候与告别')
      expect(hint.hintEn).toContain('morning')
    })

    it('should generate hint for all curriculum categories', () => {
      const categories = [
        'greetings_and_farewells',
        'numbers',
        'colors',
        'animals',
        'family',
        'body',
        'food_and_drink',
        'clothes',
        'school',
        'weather_and_seasons',
        'time_and_daily_routine',
        'places_and_directions',
        'emotions_and_feelings',
        'actions_and_verbs',
        'adjectives_and_adverbs',
        'pronouns_and_prepositions',
      ]
      for (const cat of categories) {
        const hint = detector.generateSilentHint(cat)
        expect(hint.hintEn.length).toBeGreaterThan(10)
        expect(hint.hintCn.length).toBeGreaterThan(5)
      }
    })
  })

  // ============================================================
  // 3. Consecutive Error Streak Tracking
  // ============================================================

  describe('error streak tracking', () => {
    const testUser = 'test-user-error-streak'

    beforeEach(() => {
      detector.clearStreak(testUser)
    })

    it('should start with zero error streak', () => {
      expect(detector.getErrorStreak(testUser)).toBe(0)
    })

    it('should increment error streak on each error', () => {
      detector.recordError(testUser)
      expect(detector.getErrorStreak(testUser)).toBe(1)

      detector.recordError(testUser)
      expect(detector.getErrorStreak(testUser)).toBe(2)

      detector.recordError(testUser)
      expect(detector.getErrorStreak(testUser)).toBe(3)
    })

    it('should return true when error streak reaches threshold', () => {
      detector.recordError(testUser)
      detector.recordError(testUser)
      expect(detector.shouldReduceDifficulty(testUser, 3)).toBe(false)

      detector.recordError(testUser)
      expect(detector.shouldReduceDifficulty(testUser, 3)).toBe(true)
    })

    it('should use default threshold of 3', () => {
      detector.recordError(testUser)
      detector.recordError(testUser)
      detector.recordError(testUser)
      expect(detector.shouldReduceDifficulty(testUser)).toBe(true)
    })

    it('should clear streak when clearStreak is called', () => {
      detector.recordError(testUser)
      detector.recordError(testUser)
      detector.recordError(testUser)
      expect(detector.getErrorStreak(testUser)).toBe(3)

      detector.clearStreak(testUser)
      expect(detector.getErrorStreak(testUser)).toBe(0)
    })

    it('should track different users independently', () => {
      detector.recordError('user-a')
      detector.recordError('user-a')
      detector.recordError('user-b')

      expect(detector.getErrorStreak('user-a')).toBe(2)
      expect(detector.getErrorStreak('user-b')).toBe(1)
    })

    it('should work with custom threshold', () => {
      detector.recordError(testUser)
      expect(detector.shouldReduceDifficulty(testUser, 1)).toBe(true)
      expect(detector.shouldReduceDifficulty(testUser, 5)).toBe(false)
    })
  })

  // ============================================================
  // 4. Chinese Explanations
  // ============================================================

  describe('generateChineseExplanation', () => {
    it('should generate explanation for grammar errors', () => {
      const result = detector.generateChineseExplanation(
        'grammar',
        "he doesn't",
        '第三人称单数要用 doesn\'t'
      )
      expect(result).toContain('语法')
      expect(result).toContain("he doesn't")
      expect(result).toContain("第三人称单数")
    })

    it('should generate explanation for vocabulary errors', () => {
      const result = detector.generateChineseExplanation(
        'vocabulary',
        'apple',
        'apple 是苹果的意思'
      )
      expect(result).toContain('词汇')
      expect(result).toContain('apple')
    })

    it('should generate explanation for pronunciation errors', () => {
      const result = detector.generateChineseExplanation(
        'pronunciation',
        'three',
        'th 发音要咬舌尖'
      )
      expect(result).toContain('发音')
      expect(result).toContain('three')
    })

    it('should generate explanation for pragmatic errors', () => {
      const result = detector.generateChineseExplanation(
        'pragmatic',
        'Could you please...',
        '请求时用 Could you please 更礼貌'
      )
      expect(result).toContain('语用')
    })

    it('should include supportive prefix', () => {
      const result = detector.generateChineseExplanation(
        'grammar',
        'test',
        'test explanation'
      )
      const hasPrefix =
        result.includes('没关系') ||
        result.includes('小提示') ||
        result.includes('别担心') ||
        result.includes('让我们试试') ||
        result.includes('加油')
      expect(hasPrefix).toBe(true)
    })

    it('should handle unknown error types gracefully', () => {
      const result = detector.generateChineseExplanation(
        'unknown',
        'test',
        'explanation'
      )
      expect(result).toContain('语言') // fallback label
      expect(result).toContain('test')
    })

    it('should include encouraging emoji at end', () => {
      const result = detector.generateChineseExplanation(
        'grammar',
        'test',
        'explanation'
      )
      expect(result).toContain('加油')
    })
  })

  // ============================================================
  // 5. Streak Reward Detection
  // ============================================================

  describe('streak reward detection', () => {
    const testUser = 'test-user-streak-reward'

    beforeEach(() => {
      detector.clearStreak(testUser)
    })

    it('should start with zero correct streak', () => {
      expect(detector.getCorrectStreak(testUser)).toBe(0)
    })

    it('should increment correct streak on each correct answer', () => {
      detector.recordCorrect(testUser)
      expect(detector.getCorrectStreak(testUser)).toBe(1)

      detector.recordCorrect(testUser)
      expect(detector.getCorrectStreak(testUser)).toBe(2)

      detector.recordCorrect(testUser)
      expect(detector.getCorrectStreak(testUser)).toBe(3)
    })

    it('should trigger reward at threshold', () => {
      detector.recordCorrect(testUser)
      detector.recordCorrect(testUser)
      expect(detector.checkStreakReward(testUser, 3)).toBe(false)

      detector.recordCorrect(testUser)
      expect(detector.checkStreakReward(testUser, 3)).toBe(true)
    })

    it('should use default threshold of 3', () => {
      detector.recordCorrect(testUser)
      detector.recordCorrect(testUser)
      detector.recordCorrect(testUser)
      expect(detector.checkStreakReward(testUser)).toBe(true)
    })

    it('should work with custom threshold', () => {
      detector.recordCorrect(testUser)
      expect(detector.checkStreakReward(testUser, 1)).toBe(true)
      expect(detector.checkStreakReward(testUser, 5)).toBe(false)
    })

    it('should reset error streak when recording correct answer', () => {
      detector.recordError(testUser)
      detector.recordError(testUser)
      expect(detector.getErrorStreak(testUser)).toBe(2)

      detector.recordCorrect(testUser)
      expect(detector.getErrorStreak(testUser)).toBe(0)
    })

    it('should reset correct streak when recording error', () => {
      detector.recordCorrect(testUser)
      detector.recordCorrect(testUser)
      expect(detector.getCorrectStreak(testUser)).toBe(2)

      detector.recordError(testUser)
      expect(detector.getCorrectStreak(testUser)).toBe(0)
    })

    it('should track different users independently', () => {
      detector.recordCorrect('user-x')
      detector.recordCorrect('user-x')
      detector.recordCorrect('user-y')

      expect(detector.getCorrectStreak('user-x')).toBe(2)
      expect(detector.getCorrectStreak('user-y')).toBe(1)
    })
  })

  // ============================================================
  // Integration: Combined workflow
  // ============================================================

  describe('combined workflow', () => {
    const testUser = 'test-user-combined'

    beforeEach(() => {
      detector.clearStreak(testUser)
    })

    it('should handle a full learning session flow', () => {
      // Player speaks using curriculum vocabulary
      const vocabResult = detector.checkCurriculumVocabulary(
        'I see a red cat'
      )
      expect(vocabResult.hasCurriculumVocab).toBe(true)

      // Player gets 3 correct in a row -> reward
      detector.recordCorrect(testUser)
      detector.recordCorrect(testUser)
      detector.recordCorrect(testUser)
      expect(detector.checkStreakReward(testUser)).toBe(true)

      // Then player makes 3 errors -> difficulty reduction
      detector.recordError(testUser)
      detector.recordError(testUser)
      detector.recordError(testUser)
      expect(detector.shouldReduceDifficulty(testUser)).toBe(true)

      // Generate Chinese explanation for the error
      const explanation = detector.generateChineseExplanation(
        'grammar',
        'I am going',
        '正在进行时用 am going'
      )
      expect(explanation).toContain('语法')

      // Player is silent -> generate hint based on last category
      const hint = detector.generateSilentHint('animals')
      expect(hint.category).toBe('动物')
    })

    it('should alternate streaks correctly', () => {
      // Correct, Error, Correct, Correct, Correct
      detector.recordCorrect(testUser)
      expect(detector.getCorrectStreak(testUser)).toBe(1)

      detector.recordError(testUser)
      expect(detector.getCorrectStreak(testUser)).toBe(0)
      expect(detector.getErrorStreak(testUser)).toBe(1)

      detector.recordCorrect(testUser)
      detector.recordCorrect(testUser)
      detector.recordCorrect(testUser)
      expect(detector.getCorrectStreak(testUser)).toBe(3)
      expect(detector.getErrorStreak(testUser)).toBe(0)
      expect(detector.checkStreakReward(testUser)).toBe(true)
    })
  })
})
