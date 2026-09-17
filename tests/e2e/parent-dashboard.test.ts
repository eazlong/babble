import { test, expect } from '@playwright/test'

// 家长控制台 E2E —— 只读、不触碰生产数据。
// 被测对象：已部署的 docker-compose 环境（parent-dashboard:3333, auth-service:8310）。
// 安全约定：本文件不发起真实注册/登录成功请求（避免创建/污染生产账户），
// 涉及注册的请求一律用 page.route 拦截并 abort，仅断言前端发送的载荷契约。

test.describe('Parent Dashboard (read-only)', () => {
  test('unauthenticated /dashboard redirects to /login (AuthGuard)', async ({ page }) => {
    await page.goto('/dashboard')
    await expect(page).toHaveURL(/\/login/)
    // 登录表单应出现
    await expect(page.getByRole('heading', { name: 'Sign In' })).toBeVisible()
  })

  test('login page renders email/password fields', async ({ page }) => {
    await page.goto('/login')
    await expect(page.getByLabel('Email')).toBeVisible()
    await expect(page.getByLabel('Password')).toBeVisible()
    await expect(page.getByRole('button', { name: 'Sign In' })).toBeVisible()
    // 注册入口链接存在
    await expect(page.getByRole('link', { name: 'Register' })).toBeVisible()
  })

  test('register page renders all fields incl. required Parent Name', async ({ page }) => {
    await page.goto('/register')
    await expect(page.getByRole('heading', { name: 'Register' })).toBeVisible()
    await expect(page.getByLabel('Email')).toBeVisible()
    // 关键回归：新增的必填 Parent Name（display_name）字段
    await expect(page.getByLabel('Parent Name')).toBeVisible()
    await expect(page.getByLabel('Password')).toBeVisible()
    await expect(page.getByLabel(/Confirm Password/)).toBeVisible()
    await expect(page.getByLabel(/Child's Name/)).toBeVisible()
  })

  test('register sends display_name + email + password + child_name (payload contract, request aborted)', async ({
    page,
  }) => {
    // 拦截注册请求，断言载荷后直接 abort，绝不落库/触碰生产
    let capturedBody: string | null = null
    await page.route('**/api/v1/auth/register', async route => {
      capturedBody = route.request().postData()
      await route.abort()
    })

    await page.goto('/register')
    await page.getByLabel('Email').fill('e2e-parent@example.com')
    await page.getByLabel('Parent Name').fill('E2E Parent')
    await page.getByLabel('Password').fill('password123')
    await page.getByLabel(/Confirm Password/).fill('password123')
    await page.getByLabel(/Child's Name/).fill('Xiaoming')

    await page.getByRole('button', { name: 'Create Account' }).click()

    // 请求被拦截且 body 已被捕获
    await expect.poll(() => capturedBody).not.toBeNull()

    const body = JSON.parse(capturedBody!)
    // 后端 schema 契约：display_name 必填
    expect(body).toMatchObject({
      email: 'e2e-parent@example.com',
      password: 'password123',
      display_name: 'E2E Parent',
      child_name: 'Xiaoming',
    })
  })

  test('client-side required validation blocks empty submit', async ({ page }) => {
    await page.goto('/register')
    // 不填任何字段直接提交，应被浏览器 required 校验拦截（停在注册页，不发请求）
    await page.getByRole('button', { name: 'Create Account' }).click()
    // 仍在注册页，且 URL 未跳转
    await expect(page).toHaveURL(/\/register/)
  })
})
