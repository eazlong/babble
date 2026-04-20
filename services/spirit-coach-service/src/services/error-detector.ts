export type ErrorType = 'grammar' | 'vocabulary' | 'pronunciation' | 'pragmatic'
export type Severity = 'low' | 'medium' | 'high'

export interface DetectedError {
  type: ErrorType
  severity: Severity
  original_text: string
  correction: string
  explanation: string
}

// ============================================================
// Grade 4 Curriculum Vocabulary (课标词汇)
// Sourced from domestic grade 4 English teaching syllabus
// ============================================================

interface CurriculumCategory {
  name: string
  nameCn: string
  words: string[]
}

const GRADE_4_CURRICULUM: CurriculumCategory[] = [
  {
    name: 'greetings_and_farewells',
    nameCn: '问候与告别',
    words: ['hello', 'hi', 'goodbye', 'bye', 'good', 'morning', 'afternoon', 'evening', 'night', 'welcome', 'please', 'thank', 'thanks', 'sorry', 'fine'],
  },
  {
    name: 'numbers',
    nameCn: '数字',
    words: ['one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'eleven', 'twelve', 'thirteen', 'fourteen', 'fifteen', 'sixteen', 'seventeen', 'eighteen', 'nineteen', 'twenty', 'thirty', 'forty', 'fifty', 'hundred', 'first', 'second', 'third'],
  },
  {
    name: 'colors',
    nameCn: '颜色',
    words: ['red', 'blue', 'green', 'yellow', 'orange', 'purple', 'white', 'black', 'brown', 'pink', 'grey', 'gray', 'color'],
  },
  {
    name: 'animals',
    nameCn: '动物',
    words: ['cat', 'dog', 'bird', 'fish', 'rabbit', 'mouse', 'pig', 'duck', 'hen', 'cow', 'horse', 'sheep', 'goat', 'chicken', 'panda', 'monkey', 'tiger', 'lion', 'elephant', 'bear', 'snake', 'frog', 'ant', 'bee'],
  },
  {
    name: 'family',
    nameCn: '家庭成员',
    words: ['family', 'father', 'mother', 'dad', 'mom', 'brother', 'sister', 'grandpa', 'grandma', 'uncle', 'aunt', 'cousin', 'parent', 'son', 'daughter', 'baby'],
  },
  {
    name: 'body',
    nameCn: '身体部位',
    words: ['head', 'hair', 'face', 'eye', 'ear', 'nose', 'mouth', 'tooth', 'teeth', 'tongue', 'neck', 'shoulder', 'arm', 'hand', 'finger', 'leg', 'knee', 'foot', 'feet', 'body'],
  },
  {
    name: 'food_and_drink',
    nameCn: '食物与饮料',
    words: ['rice', 'noodle', 'bread', 'cake', 'egg', 'meat', 'fish', 'chicken', 'vegetable', 'fruit', 'apple', 'banana', 'orange', 'pear', 'water', 'milk', 'juice', 'tea', 'coffee', 'soup', 'hamburger', 'hot', 'dog', 'candy', 'chocolate', 'ice', 'cream', 'pizza', 'salt', 'sugar', 'sweet', 'hungry', 'thirsty', 'eat', 'drink', 'breakfast', 'lunch', 'dinner', 'food'],
  },
  {
    name: 'clothes',
    nameCn: '服装',
    words: ['shirt', 't-shirt', 'dress', 'skirt', 'pants', 'shorts', 'jacket', 'coat', 'sweater', 'sock', 'shoe', 'hat', 'cap', 'glove', 'scarf', 'uniform', 'wear', 'put', 'on'],
  },
  {
    name: 'school',
    nameCn: '学校',
    words: ['school', 'class', 'classroom', 'teacher', 'student', 'book', 'pen', 'pencil', 'ruler', 'eraser', 'bag', 'desk', 'chair', 'blackboard', 'homework', 'lesson', 'test', 'study', 'learn', 'read', 'write', 'draw', 'sing', 'dance', 'play'],
  },
  {
    name: 'weather_and_seasons',
    nameCn: '天气与季节',
    words: ['weather', 'sunny', 'cloudy', 'rainy', 'windy', 'snowy', 'hot', 'cold', 'warm', 'cool', 'spring', 'summer', 'autumn', 'fall', 'winter', 'rain', 'snow', 'sun', 'wind'],
  },
  {
    name: 'time_and_daily_routine',
    nameCn: '时间与日常作息',
    words: ['time', 'today', 'tomorrow', 'yesterday', 'week', 'month', 'year', 'day', 'hour', 'minute', "o'clock", 'monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday', 'get', 'up', 'go', 'to', 'bed', 'sleep', 'wake', 'home'],
  },
  {
    name: 'places_and_directions',
    nameCn: '地点与方向',
    words: ['home', 'house', 'room', 'kitchen', 'bedroom', 'bathroom', 'living', 'garden', 'park', 'zoo', 'shop', 'store', 'hospital', 'restaurant', 'library', 'cinema', 'street', 'road', 'here', 'there', 'near', 'far', 'behind', 'front', 'between', 'next', 'left', 'right', 'up', 'down', 'in', 'on', 'at', 'under'],
  },
  {
    name: 'emotions_and_feelings',
    nameCn: '情感与感受',
    words: ['happy', 'sad', 'angry', 'afraid', 'scared', 'tired', 'excited', 'nervous', 'surprised', 'proud', 'bored', 'fun', 'great', 'nice', 'good', 'bad', 'beautiful', 'cute', 'cool', 'love', 'like', 'want', 'need', 'feel'],
  },
  {
    name: 'actions_and_verbs',
    nameCn: '动作与动词',
    words: ['run', 'walk', 'jump', 'swim', 'fly', 'climb', 'sit', 'stand', 'open', 'close', 'give', 'take', 'make', 'come', 'look', 'see', 'watch', 'listen', 'hear', 'talk', 'speak', 'say', 'tell', 'ask', 'answer', 'help', 'show', 'find', 'know', 'think', 'try', 'can', 'will', 'would', 'should', 'must', 'may', 'do', 'does', 'did', 'have', 'has', 'had', 'is', 'am', 'are', 'was', 'were'],
  },
  {
    name: 'adjectives_and_adverbs',
    nameCn: '形容词与副词',
    words: ['big', 'small', 'long', 'short', 'tall', 'fat', 'thin', 'old', 'young', 'new', 'fast', 'slow', 'clean', 'dirty', 'easy', 'hard', 'many', 'much', 'some', 'any', 'all', 'every', 'each', 'very', 'really', 'too', 'also', 'only', 'just', 'then', 'now', 'always', 'often', 'sometimes', 'never'],
  },
  {
    name: 'pronouns_and_prepositions',
    nameCn: '代词与介词',
    words: ['i', 'you', 'he', 'she', 'it', 'we', 'they', 'me', 'him', 'her', 'us', 'them', 'my', 'your', 'his', 'its', 'our', 'their', 'this', 'that', 'these', 'those', 'who', 'what', 'where', 'when', 'why', 'how', 'which', 'with', 'for', 'from', 'about', 'of', 'and', 'but', 'or', 'so', 'because', 'if'],
  },
]

// Flatten all curriculum words into a Set for O(1) lookup
const ALL_CURRICULUM_WORDS = new Set(
  GRADE_4_CURRICULUM.flatMap((cat) => cat.words.map((w) => w.toLowerCase()))
)

// ============================================================
// Error Streak Tracking (consecutive errors per user)
// ============================================================

interface UserStreak {
  errorStreak: number
  correctStreak: number
}

const userStreaks: Map<string, UserStreak> = new Map()

function getOrCreateStreak(userId: string): UserStreak {
  if (!userStreaks.has(userId)) {
    userStreaks.set(userId, { errorStreak: 0, correctStreak: 0 })
  }
  return userStreaks.get(userId)!
}

// ============================================================
// Curriculum V Match Result
// ============================================================

export interface CurriculumVocabularyMatch {
  hasCurriculumVocab: boolean
  matchedCategories: string[]
  matchedCategoriesCn: string[]
  matchedWords: string[]
  coverageScore: number // 0-1 ratio of curriculum words to total words
}

// ============================================================
// Silent Hint
// ============================================================

export interface SilentHint {
  hintEn: string
  hintCn: string
  category: string
}

// ============================================================
// ErrorDetector Class
// ============================================================

export class ErrorDetector {
  // --- Existing analyze method (preserved) ---
  async analyze(playerInput: string, expectedLevel: string = 'A1'): Promise<DetectedError[]> {
    // MVP: Rule-based error detection (LLM analysis in production)
    const errors: DetectedError[] = []

    // Simple grammar rules for A1 level
    const lower = playerInput.toLowerCase()

    // Check for common article errors
    if (/\b(am|is|are)\b/.test(lower) && !/\b(a |an |the )\w+\s+(am|is|are)/.test(lower)) {
      // Skip - this is too simplistic for MVP
    }

    // Check for very basic patterns that A1 learners often get wrong
    if (/\bi am go\b/.test(lower)) {
      errors.push({
        type: 'grammar',
        severity: 'high',
        original_text: 'I am go',
        correction: 'I go / I am going',
        explanation: 'Use "I go" for habits or "I am going" for now.',
      })
    }

    if (/\bhe don'?t\b/.test(lower)) {
      errors.push({
        type: 'grammar',
        severity: 'high',
        original_text: "he don't",
        correction: "he doesn't",
        explanation: 'Use "doesn\'t" with he/she/it.',
      })
    }

    return errors
  }

  // ============================================================
  // 1. 教学内容匹配 — Check if input contains curriculum vocabulary
  // ============================================================

  checkCurriculumVocabulary(input: string): CurriculumVocabularyMatch {
    const lower = input.toLowerCase()
    // Tokenize: extract word-like tokens (including apostrophes for contractions)
    const tokens = lower.match(/[a-z]+(?:'[a-z]+)?/g) || []

    if (tokens.length === 0) {
      return {
        hasCurriculumVocab: false,
        matchedCategories: [],
        matchedCategoriesCn: [],
        matchedWords: [],
        coverageScore: 0,
      }
    }

    const matchedWordsSet = new Set<string>()
    const matchedCategoriesSet = new Set<string>()
    const matchedCategoriesCnSet = new Set<string>()

    for (const token of tokens) {
      if (ALL_CURRICULUM_WORDS.has(token)) {
        matchedWordsSet.add(token)
      }
    }

    // Find which categories the matched words belong to
    for (const word of matchedWordsSet) {
      for (const category of GRADE_4_CURRICULUM) {
        if (category.words.map((w) => w.toLowerCase()).includes(word)) {
          matchedCategoriesSet.add(category.name)
          matchedCategoriesCnSet.add(category.nameCn)
        }
      }
    }

    const coverageScore = matchedWordsSet.size / tokens.length

    return {
      hasCurriculumVocab: matchedWordsSet.size > 0,
      matchedCategories: Array.from(matchedCategoriesSet),
      matchedCategoriesCn: Array.from(matchedCategoriesCnSet),
      matchedWords: Array.from(matchedWordsSet),
      coverageScore,
    }
  }

  // ============================================================
  // 2. 沉默超时引导 — Generate proactive hints after silence
  // ============================================================

  generateSilentHint(curriculumCategory: string): SilentHint {
    const category = GRADE_4_CURRICULUM.find((c) => c.name === curriculumCategory)

    const hintTemplates: Record<string, { en: string; cn: string }> = {
      greetings_and_farewells: {
        en: "Try saying 'Good morning!' or 'Hello, how are you?' — these are great ways to start a conversation!",
        cn: '试试说"Good morning!（早上好）"或"Hello, how are you?（你好吗）"——这些都是开始对话的好方法！',
      },
      numbers: {
        en: "Can you count from one to ten in English? Let's try together: one, two, three...",
        cn: '你能用英语从一数到十吗？我们一起试试：one, two, three...',
      },
      colors: {
        en: "Look around — what color do you see? Try saying 'I see a red...' or 'It is blue!'",
        cn: '看看周围——你看到了什么颜色？试试说"I see a red...（我看到红色的...）"',
      },
      animals: {
        en: "What's your favorite animal? Try saying 'I like cats' or 'I can see a dog!'",
        cn: '你最喜欢的动物是什么？试试说"I like cats（我喜欢猫）"',
      },
      family: {
        en: "Tell me about your family! Try 'This is my mother' or 'I love my family.'",
        cn: '跟我聊聊你的家人吧！试试说"This is my mother（这是我的妈妈）"',
      },
      body: {
        en: "Touch your nose and say 'This is my nose!' — let's learn body parts together!",
        cn: '摸摸你的鼻子说"This is my nose!（这是我的鼻子）"——我们一起学习身体部位！',
      },
      food_and_drink: {
        en: "What do you like to eat? Try 'I like apples' or 'I want some water.'",
        cn: '你喜欢吃什么？试试说"I like apples（我喜欢苹果）"',
      },
      clothes: {
        en: "What are you wearing today? Try 'I wear a blue shirt' or 'I like my dress!'",
        cn: '你今天穿了什么？试试说"I wear a blue shirt（我穿了一件蓝衬衫）"',
      },
      school: {
        en: "What do you do at school? Try 'I read a book' or 'I like my teacher!'",
        cn: '你在学校做什么？试试说"I read a book（我读书）"',
      },
      weather_and_seasons: {
        en: "What's the weather like today? Try 'It is sunny' or 'I like summer!'",
        cn: '今天天气怎么样？试试说"It is sunny（今天是晴天）"',
      },
      time_and_daily_routine: {
        en: "What time do you get up? Try 'I get up at seven' or 'It is time for bed.'",
        cn: '你几点起床？试试说"I get up at seven（我七点起床）"',
      },
      places_and_directions: {
        en: "Where are you going? Try 'I go to school' or 'The park is near my home.'",
        cn: '你要去哪里？试试说"I go to school（我去学校）"',
      },
      emotions_and_feelings: {
        en: "How do you feel today? Try 'I am happy' or 'I feel excited!'",
        cn: '你今天感觉怎么样？试试说"I am happy（我很开心）"',
      },
      actions_and_verbs: {
        en: "What can you do? Try 'I can run' or 'I like to swim!'",
        cn: '你会做什么？试试说"I can run（我会跑步）"',
      },
      adjectives_and_adverbs: {
        en: "Describe something! Try 'The cat is big' or 'It is very nice!'",
        cn: '描述一样东西！试试说"The cat is big（猫很大）"',
      },
      pronouns_and_prepositions: {
        en: "Try using 'he', 'she', or 'they' — like 'She is my teacher' or 'He is tall!'",
        cn: '试试用"he（他）"、"she（她）"或"they（他们）"——比如"She is my teacher（她是我的老师）"',
      },
    }

    if (category && hintTemplates[curriculumCategory]) {
      const template = hintTemplates[curriculumCategory]
      return {
        hintEn: template.en,
        hintCn: template.cn,
        category: category.nameCn,
      }
    }

    // Fallback generic hint
    return {
      hintEn: "You're doing great! Try saying something in English — even a simple word is a good start. I'm here to help!",
      hintCn: '你做得很好！试试说一些英语——哪怕是一个简单的单词也是好的开始。我在这里帮你！',
      category: '通用',
    }
  }

  // ============================================================
  // 3. 连错降级逻辑 — Track consecutive errors, auto-reduce difficulty
  // ============================================================

  recordError(userId: string): void {
    const streak = getOrCreateStreak(userId)
    streak.errorStreak += 1
    streak.correctStreak = 0 // Reset correct streak on error
  }

  clearStreak(userId: string): void {
    const streak = getOrCreateStreak(userId)
    streak.errorStreak = 0
    streak.correctStreak = 0
  }

  getErrorStreak(userId: string): number {
    const streak = getOrCreateStreak(userId)
    return streak.errorStreak
  }

  shouldReduceDifficulty(userId: string, threshold: number = 3): boolean {
    return this.getErrorStreak(userId) >= threshold
  }

  // ============================================================
  // 4. 中文辅助模式 — Generate Chinese explanations for errors
  // ============================================================

  generateChineseExplanation(
    errorType: string,
    correctForm: string,
    explanation: string
  ): string {
    const typeLabels: Record<string, string> = {
      grammar: '语法',
      vocabulary: '词汇',
      pronunciation: '发音',
      pragmatic: '语用',
    }

    const typeLabel = typeLabels[errorType] || '语言'

    const supportivePrefixes = [
      '没关系！我们来看看这个：',
      '小提示：',
      '别担心，这个很容易学会：',
      '让我们试试这样说：',
      '加油！正确的是：',
    ]
    const prefix = supportivePrefixes[Math.floor(Math.random() * supportivePrefixes.length)]

    return `${prefix}【${typeLabel}】正确说法是："${correctForm}"。\n${explanation}\n💪 你已经很棒了，继续加油！`
  }

  // ============================================================
  // 5. 连击奖励检测 — Track correct streaks, trigger bonus
  // ============================================================

  recordCorrect(userId: string): void {
    const streak = getOrCreateStreak(userId)
    streak.correctStreak += 1
    streak.errorStreak = 0 // Reset error streak on correct answer
  }

  getCorrectStreak(userId: string): number {
    const streak = getOrCreateStreak(userId)
    return streak.correctStreak
  }

  checkStreakReward(userId: string, threshold: number = 3): boolean {
    return this.getCorrectStreak(userId) >= threshold
  }
}
