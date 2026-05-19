import { ErrorDetector } from './error-detector.js'
import { CoachInput, interventionPriority } from '../types/coach-events.js'

export class TriggerClassifier {
  constructor(private readonly errorDetector: ErrorDetector) {}

  async classify(input: CoachInput) {
    if (input.event_type === 'wake_request') {
      return {
        trigger: 'wake' as const,
        priority: interventionPriority.wake,
        input,
        errors: [],
      }
    }

    if (input.event_type === 'silence_timeout') {
      return {
        trigger: 'silence' as const,
        priority: interventionPriority.silence,
        input,
        errors: [],
      }
    }

    const errors = await this.errorDetector.analyze(input.player_text)
    const highSeverityErrors = errors.filter((error) => error.severity === 'high')

    if (highSeverityErrors.length === 0) {
      return null
    }

    return {
      trigger: 'error' as const,
      priority: interventionPriority.error,
      input,
      errors: highSeverityErrors,
    }
  }
}
