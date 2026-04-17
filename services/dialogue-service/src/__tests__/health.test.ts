import { test, expect } from 'vitest'
import app from '../index'

test('GET /health returns ok status', async () => {
  const response = await app.inject({
    method: 'GET',
    url: '/health'
  })
  expect(response.statusCode).toBe(200)
  const body = JSON.parse(response.body)
  expect(body.status).toBe('ok')
  expect(body.service).toBe('dialogue-service')
})
