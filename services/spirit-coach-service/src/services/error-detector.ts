export type ErrorType = 'grammar' | 'vocabulary' | 'pronunciation' | 'pragmatic'
export type Severity = 'low' | 'medium' | 'high'

export interface DetectedError {
  type: ErrorType
  severity: Severity
  original_text: string
  correction: string
  explanation: string
}

export class ErrorDetector {
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
        explanation: 'Use "I go" for habits or "I am going" for now.'
      })
    }

    if (/\bhe don'?t\b/.test(lower)) {
      errors.push({
        type: 'grammar',
        severity: 'high',
        original_text: 'he don\'t',
        correction: 'he doesn\'t',
        explanation: 'Use "doesn\'t" with he/she/it.'
      })
    }

    return errors
  }
}
