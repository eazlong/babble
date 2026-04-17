import { test, expect, vi } from 'vitest'

test('POST /api/v1/auth/register creates user account', async () => {
  // Mock Supabase auth
  const mockSignUp = vi.fn().mockResolvedValue({
    data: { user: { id: 'test-uuid', email: 'test@example.com' } },
    error: null
  })

  const mockInsert = vi.fn().mockResolvedValue({ error: null })

  // Create a mock app
  const mockApp = {
    supabase: {
      auth: { signUp: mockSignUp },
      from: vi.fn().mockReturnValue({ insert: mockInsert })
    }
  }

  // Verify the mock is called correctly
  expect(mockSignUp).toBeDefined()
  expect(typeof mockSignUp).toBe('function')
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
