/**
 * NPCSpawner - Reads NPC positions from SceneConfig and instantiates NPCBase prefabs
 * at the correct positions in the world layer.
 */

import { _decorator, Component, Node, instantiate, Prefab } from 'cc'
import { CCGlobalState } from '../Integration/CCGlobalState'
import { CCSceneManager } from '../Integration/CCSceneManager'

const { ccclass, property } = _decorator

@ccclass('NPCSpawner')
export class NPCSpawner extends Component {
  @property(Prefab) npcBasePrefab: Prefab | null = null
  @property(Node) spawnParent: Node | null = null

  start() {
    this.node.on('scene_entered', (sceneId: string) => {
      this.spawnNPCs(sceneId)
    })
  }

  spawnNPCs(sceneId: string): void {
    const state = CCGlobalState.getInstance()
    const sceneMgr = new CCSceneManager()

    // Get NPC positions from scene config
    const npcs = sceneMgr.getAvailableNPCs()
    if (npcs.length === 0) return

    const spawnTarget = this.spawnParent ?? this.node

    for (const npc of npcs) {
      if (!this.npcBasePrefab) continue

      const instance = instantiate(this.npcBasePrefab)
      instance.setPosition(npc.position.x, npc.position.y, 0)
      instance.name = `NPC_${npc.npc_id}`
      spawnTarget.addChild(instance)

      // Set NPC ID via component (set by CocosCreator at edit time)
      const controller = instance.getComponent('NPCController') as { npcId: string } | null
      if (controller) {
        controller.npcId = npc.npc_id
      }
    }
  }
}
