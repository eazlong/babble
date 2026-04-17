export interface ModerationResult {
  safe: boolean
  categories: Record<string, boolean>
  flagged_categories: string[]
}

export class ContentFilter {
  private blockedPatterns: RegExp[]

  constructor() {
    this.blockedPatterns = [
      /(?:kill|die|death|hurt)/i,
      /(?:blood|weapon|fight)/i,
    ]
  }

  async check(text: string, isChildMode: boolean = false): Promise<ModerationResult> {
    const flaggedCategories: string[] = []

    // Layer 2: Custom rule engine (MVP: skip OpenAI API, use regex only)
    if (isChildMode) {
      for (const pattern of this.blockedPatterns) {
        if (pattern.test(text)) {
          flaggedCategories.push('child_unsafe')
        }
      }
    }

    return {
      safe: flaggedCategories.length === 0,
      categories: {},
      flagged_categories: flaggedCategories
    }
  }
}
