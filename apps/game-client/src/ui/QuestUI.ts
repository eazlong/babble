import { Label, Node } from 'cc'

export interface QuestDisplayInfo {
  title: string
  description: string
  progress: number
  total: number
  reward_lxp: number
}

export class QuestUI {
  private questPanel: Node
  private questTitleLabel: Label
  private questDescLabel: Label
  private questProgressLabel: Label

  constructor(rootNode: Node) {
    this.questPanel = rootNode.getChildByName('QuestPanel')!
    this.questTitleLabel = rootNode.getChildByName('QuestTitle')!.getComponent(Label)!
    this.questDescLabel = rootNode.getChildByName('QuestDesc')!.getComponent(Label)!
    this.questProgressLabel = rootNode.getChildByName('QuestProgress')!.getComponent(Label)!
  }

  displayQuest(quest: QuestDisplayInfo): void {
    this.questTitleLabel.string = quest.title
    this.questDescLabel.string = quest.description
    this.questProgressLabel.string = `${quest.progress}/${quest.total} (+${quest.reward_lxp} LXP)`
    this.questPanel.active = true
  }

  hide(): void {
    this.questPanel.active = false
  }

  updateProgress(progress: number, total: number): void {
    this.questProgressLabel.string = `${progress}/${total}`
  }
}
