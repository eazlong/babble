import { DetectedError } from './error-detector.js'

export class CoachHintGenerator {
  generate({ trigger, errors }: { trigger: 'wake' | 'error' | 'silence'; errors: DetectedError[] }) {
    if (trigger === 'wake') {
      return {
        text: '我来帮你！你可以说：Can you help me?',
        repeat_phrase: 'Can you help me?',
        emotion: 'encourage',
        should_tts: true,
        ttl_ms: 8000,
      }
    }

    if (trigger === 'silence') {
      return {
        text: '想不出来也没关系，可以试试说：I need help.',
        repeat_phrase: 'I need help.',
        emotion: 'neutral',
        should_tts: true,
        ttl_ms: 8000,
      }
    }

    const firstError = errors[0]
    return {
      text: `差一点点！可以说：${firstError.correction}`,
      repeat_phrase: firstError.correction,
      emotion: 'encourage',
      should_tts: true,
      ttl_ms: 8000,
    }
  }
}
