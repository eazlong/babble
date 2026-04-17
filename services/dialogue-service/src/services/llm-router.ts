export type TaskType = 'npc_dialogue' | 'vocabulary_explain' | 'pronunciation_demo' | 'coach_analysis' | 'quest_narration'

export interface LLMResponse {
  text: string
  model_used: string
  deployment_mode: 'cloud' | 'local'
  prompt_tokens: number
  completion_tokens: number
  latency_ms: number
}

export class LLMRouter {
  async generate(prompt: string, taskType: TaskType, maxTokens: number = 200): Promise<LLMResponse> {
    const startTime = Date.now()

    if (this.isSimpleTask(taskType)) {
      return {
        text: 'Hello',
        model_used: 'gpt-4o-mini',
        deployment_mode: 'cloud',
        prompt_tokens: 10,
        completion_tokens: 5,
        latency_ms: Date.now() - startTime
      }
    }

    return {
      text: 'Welcome to the tavern...',
      model_used: 'gpt-4o',
      deployment_mode: 'cloud',
      prompt_tokens: 500,
      completion_tokens: 200,
      latency_ms: Date.now() - startTime
    }
  }

  private isSimpleTask(taskType: TaskType): boolean {
    return taskType === 'vocabulary_explain' || taskType === 'pronunciation_demo'
  }
}
