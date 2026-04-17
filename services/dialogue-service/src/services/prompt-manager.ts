export interface NPCProfile {
  name: string
  npc_type: string
  language_style: string
  formality: 'formal' | 'informal' | 'mixed'
  vocabulary_level: 'basic' | 'intermediate' | 'advanced'
  personality: string
}

export class PromptManager {
  static buildNPCSystemPrompt(npc: NPCProfile, playerCefrLevel: string): string {
    return `你是 "${npc.name}"，一个${npc.npc_type}。
语言风格：${npc.language_style}
正式程度：${npc.formality}
词汇等级：${npc.vocabulary_level}（对应用户 CEFR ${playerCefrLevel}）
性格：${npc.personality}

规则：
1. 始终保持在角色中
2. 根据玩家的 CEFR 等级调整词汇和句式复杂度
3. 当玩家语法错误时，以角色身份自然引导重新表达，不要直接指出错误
4. 每次回复控制在 3 句话以内
5. 使用目标语言回复（玩家母语仅用于引导）
6. 不要生成任何暴力、色情或不当内容`
  }

  static buildDialogueContext(history: Array<{speaker: string, text: string}>): string {
    if (history.length === 0) return ''
    const recent = history.slice(-4)
    return recent.map(h => `${h.speaker}: ${h.text}`).join('\n')
  }
}
