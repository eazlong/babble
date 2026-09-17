import { test, expect, describe, afterEach } from 'vitest'
import Fastify, { type FastifyInstance } from 'fastify'
import websocket from '@fastify/websocket'
import WebSocket from 'ws'
import { QuestSessionManager, createQuestEvent } from '../services/quest-session-manager.js'
import { registerQuestWsRoute } from '../routes/quest-ws.js'

// ============================================================
// /ws/quest 路由 —— 端到端回归测试
//
// 这组测试存在的原因：该路由此前**完全没有测试**，因此 @fastify/websocket
// v9 把 handler 签名从 (connection, request) 改成 (socket, request) 之后，
// 代码里残留的 `connection.socket` 一直没有被发现——它在运行时是 undefined，
// 会让整条路由抛 "Cannot read properties of undefined (reading 'on')"。
// 类型检查能抓到它，但那需要 CI 矩阵真的在跑（见下）。
// ============================================================

let app: FastifyInstance | undefined
let client: WebSocket | undefined

afterEach(async () => {
  client?.close()
  client = undefined
  await app?.close()
  app = undefined
})

async function startServer() {
  const instance = Fastify({ logger: false })
  await instance.register(websocket)
  const sessionManager = new QuestSessionManager()
  await registerQuestWsRoute(instance, sessionManager)
  await instance.listen({ port: 0, host: '127.0.0.1' })
  const address = instance.server.address()
  const port = typeof address === 'object' && address ? address.port : 0
  return { instance, sessionManager, port }
}

function open(url: string): Promise<WebSocket> {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url)
    ws.once('open', () => resolve(ws))
    ws.once('error', reject)
  })
}

function waitFor(predicate: () => boolean, timeoutMs = 2000): Promise<void> {
  return new Promise((resolve, reject) => {
    const startedAt = Date.now()
    const tick = () => {
      if (predicate()) return resolve()
      if (Date.now() - startedAt > timeoutMs) {
        return reject(new Error('waitFor: condition not met before timeout'))
      }
      setTimeout(tick, 10)
    }
    tick()
  })
}

function nextMessage(ws: WebSocket, timeoutMs = 2000): Promise<string> {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => reject(new Error('no message received')), timeoutMs)
    ws.once('message', (data) => {
      clearTimeout(timer)
      resolve(data.toString())
    })
  })
}

describe('GET /ws/quest', () => {
  test('把真实的 socket 交给 session manager，事件能送达客户端', async () => {
    const started = await startServer()
    app = started.instance

    client = await open(`ws://127.0.0.1:${started.port}/ws/quest?user_id=alice`)
    await waitFor(() => started.sessionManager.getConnectionCount() === 1)

    // 关键断言：session manager 拿到的必须是真正的 WebSocket。
    // 若传入的是 undefined，sendToUser 读 ws.readyState 时会直接抛 TypeError，
    // 而这里应当返回 true 并把事件真正写出去。
    const event = createQuestEvent('badge_unlocked', { badge: 'first_steps' })
    expect(started.sessionManager.sendToUser('alice', event)).toBe(true)

    expect(JSON.parse(await nextMessage(client))).toMatchObject({
      type: 'badge_unlocked',
      payload: { badge: 'first_steps' }
    })
  })

  test('user_id 为空时以 1008 关闭连接', async () => {
    const started = await startServer()
    app = started.instance

    const closeCode = await new Promise<number>((resolve, reject) => {
      const ws = new WebSocket(`ws://127.0.0.1:${started.port}/ws/quest?user_id=`)
      const timer = setTimeout(() => reject(new Error('connection was not closed')), 2000)
      ws.once('close', (code) => {
        clearTimeout(timer)
        resolve(code)
      })
      ws.once('error', (err) => {
        clearTimeout(timer)
        reject(err)
      })
    })

    expect(closeCode).toBe(1008)
  })

  test('客户端断开后 session manager 会解绑', async () => {
    const started = await startServer()
    app = started.instance

    client = await open(`ws://127.0.0.1:${started.port}/ws/quest?user_id=bob`)
    await waitFor(() => started.sessionManager.getConnectionCount() === 1)

    client.close()
    await waitFor(() => started.sessionManager.getConnectionCount() === 0)
    expect(started.sessionManager.getConnectionCount()).toBe(0)
  })
})
