import { FastifyInstance } from 'fastify'
import scenesData from '../data/scenes.json'

export async function registerSceneRoutes(server: FastifyInstance) {
  server.get('/api/v1/scenes', async () => {
    return { success: true, data: scenesData }
  })

  server.get('/api/v1/scenes/:sceneId', async (request, reply) => {
    const { sceneId } = request.params as { sceneId: string }
    const scene = scenesData.find(s => s.scene_id === sceneId)
    if (!scene) {
      return reply.code(404).send({ success: false, error: 'Scene not found' })
    }
    return { success: true, data: scene }
  })
}
