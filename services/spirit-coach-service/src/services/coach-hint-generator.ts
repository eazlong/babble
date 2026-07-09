import { DetectedError } from './error-detector.js'

/**
 * 小飞猫提示生成器
 *
 * 角色设定：
 * - 名字：小飞猫 (Xiao Fei Mao)
 * - 身份：玩家的伴生精灵，会飞的小猫精灵
 * - 性格：温暖、鼓励、耐心，从不批评
 * - 世界观：山海经国风奇幻，混沌迷雾笼罩世界
 * - 双语策略：根据玩家年级动态调整中英比例
 *   - 低年级 (A1): 90% 中文 + 10% 英文
 *   - 中年级 (A2): 50% 中文 + 50% 英文
 *   - 高年级 (B1-B2): 30% 中文 + 70% 英文
 */

export class CoachHintGenerator {
  private playerLevel: string = 'A1'  // 默认 A1，后续从 session 中读取

  setPlayerLevel(level: string) {
    this.playerLevel = level
  }

  generate({ trigger, errors }: { trigger: 'wake' | 'error' | 'silence'; errors: DetectedError[] }) {
    if (trigger === 'wake') {
      return {
        text: this.getWakeHint(),
        repeat_phrase: 'Can you help me?',
        emotion: 'encourage',
        should_tts: true,
        ttl_ms: 8000,
      }
    }

    if (trigger === 'silence') {
      return {
        text: this.getSilenceHint(),
        repeat_phrase: 'I need help.',
        emotion: 'neutral',
        should_tts: true,
        ttl_ms: 8000,
      }
    }

    const firstError = errors[0]
    return {
      text: this.getErrorHint(firstError),
      repeat_phrase: firstError.correction,
      emotion: 'encourage',
      should_tts: true,
      ttl_ms: 8000,
    }
  }

  /**
   * 唤醒提示（玩家主动呼唤小飞猫）
   */
  private getWakeHint(): string {
    const hints = {
      A1: '喵~ 小飞猫来啦！试试说：Can you help me?',
      A2: '喵~ 我来帮你！Try saying: Could you help me, please?',
      B1: '喵~ 别担心，可以说：Could you tell me how to...?',
      B2: '喵~ 试试更礼貌的表达：Would you mind helping me with...?',
    }
    return hints[this.playerLevel as keyof typeof hints] ?? hints.A1
  }

  /**
   * 沉默提示（玩家卡壳超过阈值）
   */
  private getSilenceHint(): string {
    const hints = {
      A1: '喵~ 想不出来也没关系，可以试试说：I need help.',
      A2: '喵~ 慢慢来，不着急。Try: I would like some help, please.',
      B1: '喵~ 卡住了？试试：I\'m not sure how to say this. Can you help?',
      B2: '喵~ 深呼吸，可以这样说：I\'m having trouble expressing myself. Could you assist me?',
    }
    return hints[this.playerLevel as keyof typeof hints] ?? hints.A1
  }

  /**
   * 错误纠正提示（玩家说错后）
   */
  private getErrorHint(error: DetectedError): string {
    const encouragements = [
      '喵~ 差一点点！',
      '喵~ 加油，再试一次！',
      '喵~ 很接近了！',
      '喵~ 别灰心！',
    ]
    const randomEncouragement = encouragements[Math.floor(Math.random() * encouragements.length)]
    return `${randomEncouragement} 可以说：${error.correction}`
  }
}
