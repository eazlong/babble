import { test, expect } from 'vitest'
import { DropEngine, Rarity } from '../services/drop-engine'

test('rollRarity returns valid rarity for main quest', () => {
  const engine = new DropEngine()
  const rarity = engine.rollRarity('main')
  expect(['common', 'rare', 'epic', 'legendary']).toContain(rarity)
})

test('rollRarity returns valid rarity for daily quest', () => {
  const engine = new DropEngine()
  const rarity = engine.rollRarity('daily')
  expect(['common', 'rare', 'epic']).toContain(rarity)
})

test('calculateDrop returns a valid drop result', async () => {
  const engine = new DropEngine()
  const drop = await engine.calculateDrop('user-1', 'main', 'A1')

  expect(drop).not.toBeNull()
  expect(drop!.item_id).toBeTruthy()
  expect(drop!.name).toBeTruthy()
  expect(['common', 'rare', 'epic', 'legendary', 'limited']).toContain(drop!.rarity)
})
