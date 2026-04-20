/**
 * QuestOverlay - Canvas-layer quest panel controller.
 * Instantiates the QuestPanel prefab and wraps the existing QuestUI class.
 */

import { _decorator, Component, Node, instantiate, Prefab } from 'cc'
import { QuestUI } from '../game-client/ui/QuestUI'
import { CCGlobalState } from '../Integration/CCGlobalState'

const { ccclass, property } = _decorator

@ccclass('QuestOverlay')
export class QuestOverlay extends Component {
  @property(Prefab) questPanelPrefab: Prefab | null = null

  private questUI: QuestUI | null = null
  private activePanel: Node | null = null

  start() {
    // Listen for quest update events
    this.node.on('update_quest', (quest) => {
      this.displayQuest(quest)
    })
  }

  displayQuest(quest: {
    title: string
    title_en: string
    description: string
    progress: number
    total: number
    reward_lxp: number
    star_rating: number
    sub_quests?: Array<{
      sub_quest_id: string
      title: string
      title_en: string
      completed: boolean
    }>
  }): void {
    if (!this.activePanel && this.questPanelPrefab) {
      this.activePanel = instantiate(this.questPanelPrefab)
      this.node.addChild(this.activePanel)
      this.questUI = new QuestUI(this.activePanel)
    }

    if (this.questUI) {
      this.questUI.displayQuest(quest)
    }
  }

  hide(): void {
    this.questUI?.hide()
  }
}
