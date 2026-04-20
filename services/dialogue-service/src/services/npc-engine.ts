import { LLMRouter, LLMResponse } from './llm-router.js'
import { PromptManager, NPCProfile } from './prompt-manager.js'

export interface DialogueRequest {
  user_id: string
  npc_id: string
  player_input: string
  session_id: string
  language: string
  cefr_level: string
  quest_context?: string
}

export interface DialogueResponse {
  npc_text: string
  audio_url: string
  lxp_earned: number
  flagged: boolean
}

class SimpleContentFilter {
  private blockedPatterns: RegExp[] = [
    /(?:kill|die|death|hurt)/i,
    /(?:blood|weapon|fight)/i,
  ]

  async check(text: string, isChildMode: boolean = false): Promise<{ safe: boolean }> {
    if (!isChildMode) return { safe: true }
    for (const pattern of this.blockedPatterns) {
      if (pattern.test(text)) return { safe: false }
    }
    return { safe: true }
  }
}

const ENCOURAGING_RESPONSES: string[] = [
  "Good try! Let me help you.",
  "That's close! Try saying it this way.",
  "You're doing great! Let's try again.",
  "Nice effort! Here's how we say it.",
]

interface PerformanceRecord {
  totalAttempts: number
  correctAttempts: number
  lastAccuracy: number
}

export class NPCEngine {
  private llmRouter: LLMRouter
  private contentFilter: SimpleContentFilter
  private performanceTracker: Map<string, PerformanceRecord>

  constructor() {
    this.llmRouter = new LLMRouter()
    this.contentFilter = new SimpleContentFilter()
    this.performanceTracker = new Map()
  }

  /**
   * Check if the player's input matches vocabulary from the NPC's teaching topics.
   * Returns a match score (0.0 - 1.0) and matched terms.
   */
  matchesCurriculumVocabulary(
    playerInput: string,
    teaches: string[]
  ): { score: number; matchedTopics: string[] } {
    if (teaches.length === 0) return { score: 0, matchedTopics: [] }

    const input = playerInput.toLowerCase()
    const matchedTopics: string[] = []

    for (const topic of teaches) {
      const topicLower = topic.toLowerCase()
      // Check if the topic keyword appears in the input
      if (input.includes(topicLower)) {
        matchedTopics.push(topic)
        continue
      }
      // Check for topic-related keywords
      const topicKeywords = this.getTopicKeywords(topicLower)
      if (topicKeywords.some(kw => input.includes(kw))) {
        matchedTopics.push(topic)
      }
    }

    const score = teaches.length > 0 ? matchedTopics.length / teaches.length : 0
    return { score, matchedTopics }
  }

  /**
   * Get common English keywords associated with a teaching topic.
   */
  private getTopicKeywords(topic: string): string[] {
    const keywordMap: Record<string, string[]> = {
      'greetings': ['hello', 'hi', 'hey', 'good morning', 'good afternoon', 'good evening', 'how are you', 'nice to meet', 'goodbye', 'bye'],
      'farewells': ['goodbye', 'bye', 'see you', 'take care', 'farewell', 'good night'],
      'numbers': ['one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten', 'hundred', 'thousand', 'first', 'second', 'third'],
      'colors': ['red', 'blue', 'green', 'yellow', 'orange', 'purple', 'pink', 'black', 'white', 'brown', 'gray', 'colour', 'color'],
      'animals': ['cat', 'dog', 'bird', 'fish', 'horse', 'cow', 'pig', 'chicken', 'duck', 'rabbit', 'tiger', 'lion', 'elephant', 'monkey', 'panda', 'bear'],
      'food': ['apple', 'banana', 'rice', 'bread', 'egg', 'milk', 'water', 'chicken', 'fish', 'vegetable', 'fruit', 'cake', 'noodle', 'soup', 'tea', 'juice', 'hungry', 'eat', 'drink', 'breakfast', 'lunch', 'dinner', 'like'],
      'family': ['mother', 'father', 'mom', 'dad', 'mum', 'brother', 'sister', 'parent', 'grandma', 'grandpa', 'uncle', 'aunt', 'cousin', 'family', 'son', 'daughter', 'baby'],
      'school': ['teacher', 'student', 'class', 'school', 'book', 'pen', 'pencil', 'homework', 'study', 'learn', 'read', 'write', 'desk', 'chair', 'classroom'],
      'body_parts': ['head', 'hand', 'foot', 'feet', 'eye', 'ear', 'nose', 'mouth', 'arm', 'leg', 'finger', 'hair', 'face', 'body', 'tooth', 'teeth', 'shoulder', 'knee'],
      'weather': ['sunny', 'rainy', 'cloudy', 'windy', 'snow', 'hot', 'cold', 'warm', 'cool', 'weather', 'storm', 'rain', 'snow'],
      'time': ['morning', 'afternoon', 'evening', 'night', 'today', 'tomorrow', 'yesterday', 'week', 'month', 'year', 'hour', 'minute', 'day', 'o\'clock', 'time', 'when', 'what time'],
      'clothing': ['shirt', 'dress', 'shoes', 'hat', 'coat', 'pants', 'socks', 'jacket', 'skirt', 'sweater', 'wear', 'clothes'],
      'transportation': ['car', 'bus', 'bike', 'bicycle', 'train', 'plane', 'airplane', 'ship', 'boat', 'walk', 'ride', 'drive', 'taxi'],
      'feelings': ['happy', 'sad', 'angry', 'scared', 'excited', 'tired', 'hungry', 'thirsty', 'bored', 'worried', 'surprised', 'nervous', 'feel'],
      'places': ['home', 'school', 'park', 'shop', 'store', 'hospital', 'restaurant', 'library', 'zoo', 'market', 'supermarket', 'cinema', 'bank', 'house', 'room'],
      'hobbies': ['play', 'game', 'sport', 'music', 'dance', 'sing', 'draw', 'paint', 'swim', 'run', 'jump', 'read', 'watch', 'listen', 'like', 'love', 'fun'],
      'shopping': ['buy', 'sell', 'price', 'money', 'cost', 'cheap', 'expensive', 'dollar', 'yuan', 'pay', 'shop', 'store', 'how much'],
    }

    // Direct match or partial match
    for (const [key, keywords] of Object.entries(keywordMap)) {
      if (key === topic || key.includes(topic) || topic.includes(key)) {
        return keywords
      }
    }
    // Return the topic itself as a keyword as fallback
    return [topic]
  }

  /**
   * Build scene context description for the system prompt.
   */
  buildSceneContext(sceneId: string): string {
    const sceneDescriptions: Record<string, string> = {
      'village_square': 'You are in the village square, a bustling central area where villagers gather. There is a fountain in the center and market stalls around it.',
      'market': 'You are at the local market, where merchants sell food, clothing, and daily goods. Vendors call out to customers and bargain over prices.',
      'school': 'You are in a classroom at the village school. There are desks, a blackboard, and educational posters on the walls. The teacher stands at the front.',
      'tavern': 'You are in a cozy tavern inn. Wooden tables and chairs fill the room, with a warm fireplace and the smell of food in the air. Travelers share stories.',
      'forest': 'You are in a quiet forest path. Trees tower overhead, and you can hear birds singing and leaves rustling in the breeze.',
      'farm': 'You are on a farm with fields of crops, a barn, and farm animals grazing. The farmer tends to the land and livestock.',
      'home': 'You are inside a family home, a warm and comfortable living space with furniture, family photos, and daily household items.',
      'park': 'You are in a peaceful park with green lawns, trees, benches, and a playground. Children play and families relax outdoors.',
      'library': 'You are in a quiet library filled with bookshelves. People read and study at tables. A librarian helps visitors find books.',
      'hospital': 'You are at a small clinic or hospital. There are waiting chairs, a reception desk, and medical staff in white coats.',
      'restaurant': 'You are in a restaurant with dining tables, a menu, and a kitchen. Waiters take orders and serve food.',
    }

    return sceneDescriptions[sceneId] || `You are at a location: ${sceneId}.`
  }

  /**
   * Generate specific encouraging feedback based on the type of error.
   */
  generateEncouragement(errorType: string): string {
    const encouragements: Record<string, string[]> = {
      'grammar': [
        "Great effort! English can be tricky. Let's try it this way!",
        "You're so close! Small adjustment and it'll be perfect!",
        "Good try! Here's a tip to make it even better.",
      ],
      'pronunciation': [
        "Nice try! Let's practice that sound together.",
        "You're getting there! Listen carefully and try again.",
        "Good job trying! Here's how to say it smoothly.",
      ],
      'vocabulary': [
        "Great thinking! Let me show you the right word.",
        "You're on the right track! Here's the word we use.",
        "Good effort! This word is the one we want here.",
      ],
      'sentence_structure': [
        "Well done for trying! Let's rearrange it a bit.",
        "Good thinking! In English, we usually say it like this.",
        "Nice attempt! Let me show you the natural order.",
      ],
      'general': [
        "Good try! Let me help you.",
        "That's close! Try saying it this way.",
        "You're doing great! Let's try again.",
        "Nice effort! Here's how we say it.",
      ],
    }

    const options = encouragements[errorType] || encouragements['general']
    return options[Math.floor(Math.random() * options.length)]
  }

  /**
   * Track player performance for a session.
   */
  trackPerformance(sessionId: string, isCorrect: boolean): void {
    const record = this.performanceTracker.get(sessionId) || {
      totalAttempts: 0,
      correctAttempts: 0,
      lastAccuracy: 0,
    }
    record.totalAttempts++
    if (isCorrect) record.correctAttempts++
    record.lastAccuracy = record.correctAttempts / record.totalAttempts
    this.performanceTracker.set(sessionId, record)
  }

  /**
   * Adjust CEFR difficulty level based on player accuracy.
   * High accuracy (>80%) suggests moving up, low accuracy (<40%) suggests moving down.
   */
  adjustDifficulty(currentLevel: string, accuracy: number): string {
    const levels = ['A1', 'A2', 'B1', 'B2', 'C1', 'C2']
    const currentIndex = levels.indexOf(currentLevel)
    if (currentIndex === -1) return currentLevel

    if (accuracy >= 0.8 && currentIndex < levels.length - 1) {
      return levels[currentIndex + 1]
    }
    if (accuracy < 0.4 && currentIndex > 0) {
      return levels[currentIndex - 1]
    }
    return currentLevel
  }

  buildTeachingContext(npc: NPCProfile): string | null {
    if (!npc.teaches || npc.teaches.length === 0) return null
    const topics = npc.teaches.join(', ')
    return `I am teaching: ${topics}. Use simple A1-level English. Encourage the student.`
  }

  async processDialogue(
    request: DialogueRequest,
    npc: NPCProfile,
    history: Array<{speaker: string, text: string}>
  ): Promise<DialogueResponse> {
    let systemPrompt = PromptManager.buildNPCSystemPrompt(npc, request.cefr_level)

    // Add scene context if NPC has a scene_id
    if (npc.scene_id) {
      const sceneContext = this.buildSceneContext(npc.scene_id)
      systemPrompt = `${systemPrompt}\n\n${sceneContext}`
    }

    const teachingContext = this.buildTeachingContext(npc)
    if (teachingContext) {
      systemPrompt = `${systemPrompt}\n\n${teachingContext}`
    }

    // Check if player input matches curriculum vocabulary
    if (npc.teaches && npc.teaches.length > 0) {
      const vocabMatch = this.matchesCurriculumVocabulary(request.player_input, npc.teaches)
      if (vocabMatch.score > 0) {
        systemPrompt = `${systemPrompt}\n\nThe player is using vocabulary related to: ${vocabMatch.matchedTopics.join(', ')}. Acknowledge and reinforce their learning.`
      }
    }

    const context = PromptManager.buildDialogueContext(history)

    const userPrompt = context
      ? `${context}\n\nPlayer: ${request.player_input}\n\nRespond as ${npc.name}:`
      : `Player: ${request.player_input}\n\nRespond as ${npc.name}:`

    const fullPrompt = request.quest_context
      ? `${userPrompt}\n\n[Current quest: ${request.quest_context}]`
      : userPrompt

    const llmResponse = await this.llmRouter.generate(
      `${systemPrompt}\n\n${fullPrompt}`,
      'npc_dialogue',
      300
    )

    const moderation = await this.contentFilter.check(llmResponse.text)

    if (!moderation.safe) {
      return {
        npc_text: this.generateEncouragement('general'),
        audio_url: '',
        lxp_earned: 0,
        flagged: true
      }
    }

    return {
      npc_text: llmResponse.text,
      audio_url: '',
      lxp_earned: this.calculateLXP(request.player_input, llmResponse.text),
      flagged: false
    }
  }

  private calculateLXP(playerInput: string, _npcResponse: string): number {
    const words = playerInput.split(/\s+/).length
    return Math.min(100, Math.max(10, words * 5))
  }
}
