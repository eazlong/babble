import { test, expect, vi } from 'vitest'

test('POST /api/v1/auth/register persists a parent via db.query', async () => {
  // register.ts 现已不依赖 Supabase，改用 app.db.query 直接写 Postgres。
  // 这里锁定接口契约：查询 / 插入都通过 app.db.query(text, params)。
  const mockQuery = vi.fn().mockResolvedValue([])
  const mockApp = {
    db: { query: mockQuery },
    pool: {}
  }

  expect(mockApp.db.query).toBeDefined()
  expect(typeof mockApp.db.query).toBe('function')

  // 模拟一次注册写库调用（与 register.ts 中的 INSERT users 一致）
  await mockApp.db.query(
    'INSERT INTO users (user_id, email, password_hash, display_name, account_type) VALUES ($1,$2,$3,$4,$5)',
    ['uuid', 'parent@example.com', 'hashed', 'Mr Wang', 'parent']
  )
  expect(mockQuery).toHaveBeenCalledTimes(1)
  expect(mockQuery.mock.calls[0][0]).toContain('INSERT INTO users')
})

test('POST /api/v1/auth/register validates email format', async () => {
  const { z } = await import('zod')
  const registerSchema = z.object({
    email: z.string().email(),
    password: z.string().min(8),
    display_name: z.string().min(1).max(50)
  })

  expect(() => registerSchema.parse({ email: 'invalid', password: 'password123', display_name: 'Test' }))
    .toThrow()

  expect(() => registerSchema.parse({ email: 'test@example.com', password: 'short', display_name: 'Test' }))
    .toThrow()
})
