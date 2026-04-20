export interface NPCProfile {
  name: string
  name_cn?: string
  role: string
  personality: string
  cefr_level: string
  voice_style?: string
  greeting?: string
  scene_id?: string
  teaches?: string[]
  is_persistent?: boolean
}

export class PromptManager {
  static buildNPCSystemPrompt(npc: NPCProfile, playerCefrLevel: string): string {
    const roleDesc = npc.role.replace(/_/g, ' ')
    return `你是 "${npc.name}"${npc.name_cn ? `（${npc.name_cn}）` : ''}，一个${roleDesc}。
性格：${npc.personality}
CEFR 等级：${npc.cefr_level}
玩家 CEFR 等级：${playerCefrLevel}

规则：
1. 始终保持在角色中
2. 根据玩家的 CEFR 等级调整词汇和句式复杂度（A1 等级使用简单短句）
3. 当玩家语法错误时，以角色身份自然引导重新表达，不要直接指出错误
4. 每次回复控制在 3 句话以内
5. 使用目标语言回复（玩家母语仅用于引导）
6. 不要生成任何暴力、色情或不当内容
7. 永远使用鼓励式反馈，不说"你错了"`
  }

  static buildDialogueContext(history: Array<{speaker: string, text: string}>): string {
    if (history.length === 0) return ''
    const recent = history.slice(-4)
    return recent.map(h => `${h.speaker}: ${h.text}`).join('\n')
  }
}
