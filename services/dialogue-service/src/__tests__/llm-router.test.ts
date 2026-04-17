import { test, expect, vi, beforeEach } from 'vitest'
import { LLMRouter, TaskType } from '../services/llm-router'

test('simple tasks route to GPT-4o-mini', async () => {
  const router = new LLMRouter()

  const result = await router.generate('Explain the word "run"', 'vocabulary_explain')
  expect(result.model_used).toBe('gpt-4o-mini')
})

test('complex tasks route to GPT-4o', async () => {
  const router = new LLMRouter()

  const result = await router.generate('You are a tavern keeper...', 'npc_dialogue')
  expect(result.model_used).toBe('gpt-4o')
})

test('pronunciation_demo is a simple task', async () => {
  const router = new LLMRouter()

  const result = await router.generate('Demo pronunciation of "hello"', 'pronunciation_demo')
  expect(result.model_used).toBe('gpt-4o-mini')
})
