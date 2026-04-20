import { FastifyInstance } from 'fastify'
import scenesData from '../data/scenes.json'

export async function registerSceneRoutes(app: FastifyInstance) {
  app.get('/api/v1/scenes', async () => {
    return scenesData
  })

  app.get('/api/v1/scenes/:sceneId', async (request, reply) => {
    const { sceneId } = request.params as { sceneId: string }
    const scene = scenesData.find(s => s.scene_id === sceneId)
    if (!scene) {
      return reply.code(404).send({ error: 'Scene not found' })
    }
    return scene
  })
}
