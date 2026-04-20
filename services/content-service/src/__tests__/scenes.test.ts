import { test, expect } from 'vitest'
import app from '../index.js'

test('GET /health returns ok', async () => {
  const res = await app.inject({ method: 'GET', url: '/health' })
  expect(res.statusCode).toBe(200)
  const body = res.json()
  expect(body.status).toBe('ok')
  expect(body.service).toBe('content-service')
})

test('GET /api/v1/scenes returns all scenes', async () => {
  const res = await app.inject({ method: 'GET', url: '/api/v1/scenes' })
  expect(res.statusCode).toBe(200)
  const scenes = res.json()
  expect(Array.isArray(scenes)).toBe(true)
  expect(scenes).toHaveLength(3)
  expect(scenes[0].scene_id).toBe('spirit_forest')
  expect(scenes[1].scene_id).toBe('spell_library')
  expect(scenes[2].scene_id).toBe('rainbow_garden')
})

test('GET /api/v1/scenes/:sceneId returns a single scene', async () => {
  const res = await app.inject({ method: 'GET', url: '/api/v1/scenes/spirit_forest' })
  expect(res.statusCode).toBe(200)
  const scene = res.json()
  expect(scene.scene_id).toBe('spirit_forest')
  expect(scene.scene_name).toBe('精灵森林')
  expect(scene.npcs).toContain('oakley')
  expect(scene.required_lxp).toBe(30)
})

test('GET /api/v1/scenes/:sceneId returns 404 for unknown scene', async () => {
  const res = await app.inject({ method: 'GET', url: '/api/v1/scenes/nonexistent' })
  expect(res.statusCode).toBe(404)
  const body = res.json()
  expect(body.error).toBe('Scene not found')
})

test('scene data has all required fields', async () => {
  const res = await app.inject({ method: 'GET', url: '/api/v1/scenes' })
  const scenes = res.json()
  const requiredFields = ['scene_id', 'scene_name', 'scene_name_en', 'order', 'description', 'npcs', 'vocabulary_focus', 'tasks', 'badge_id', 'required_lxp']
  for (const scene of scenes) {
    for (const field of requiredFields) {
      expect(scene).toHaveProperty(field)
    }
  }
})
