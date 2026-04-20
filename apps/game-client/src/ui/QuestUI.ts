import { Label, Node, ProgressBar } from 'cc'

export interface QuestDisplayInfo {
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
}

export class QuestUI {
  private questPanel: Node
  private questTitleLabel: Label
  private questDescLabel: Label
  private questProgressLabel: Label
  private questProgressBar: ProgressBar
  private starRatingContainer: Node
  private subQuestContainer: Node

  constructor(rootNode: Node) {
    this.questPanel = rootNode.getChildByName('QuestPanel')!
    this.questTitleLabel = rootNode.getChildByName('QuestTitle')!.getComponent(Label)!
    this.questDescLabel = rootNode.getChildByName('QuestDesc')!.getComponent(Label)!
    this.questProgressLabel = rootNode.getChildByName('QuestProgress')!.getComponent(Label)!
    this.questProgressBar = rootNode.getChildByName('QuestProgressBar')!.getComponent(ProgressBar)!
    this.starRatingContainer = rootNode.getChildByName('StarRating')!
    this.subQuestContainer = rootNode.getChildByName('SubQuestContainer')!
  }

  displayQuest(quest: QuestDisplayInfo): void {
    // Bilingual title display
    this.questTitleLabel.string = `${quest.title} / ${quest.title_en}`
    this.questDescLabel.string = quest.description
    this.questProgressLabel.string = `${quest.progress}/${quest.total} (+${quest.reward_lxp} LXP)`

    // Progress bar
    this.questProgressBar.progress = quest.total > 0 ? quest.progress / quest.total : 0

    // Star rating
    this.renderStarRating(quest.star_rating)

    // Sub-quest grouping
    if (quest.sub_quests && quest.sub_quests.length > 0) {
      this.renderSubQuests(quest.sub_quests)
    } else {
      this.subQuestContainer.active = false
    }

    this.questPanel.active = true
  }

  hide(): void {
    this.questPanel.active = false
  }

  updateProgress(progress: number, total: number): void {
    this.questProgressLabel.string = `${progress}/${total}`
    this.questProgressBar.progress = total > 0 ? progress / total : 0
  }

  private renderStarRating(rating: number): void {
    // Clear existing stars
    for (let i = 0; i < this.starRatingContainer.children.length; i++) {
      this.starRatingContainer.children[i].active = false
    }
    // Activate stars based on rating (1-5 scale)
    for (let i = 0; i < Math.min(rating, 5); i++) {
      if (this.starRatingContainer.children[i]) {
        this.starRatingContainer.children[i].active = true
      }
    }
    this.starRatingContainer.active = rating > 0
  }

  private renderSubQuests(subQuests: QuestDisplayInfo['sub_quests']): void {
    this.subQuestContainer.active = true

    // Clear existing sub-quest entries
    for (const child of this.subQuestContainer.children) {
      child.active = false
    }

    // Render each sub-quest with completion status
    for (let i = 0; i < (subQuests?.length ?? 0); i++) {
      const sq = subQuests![i]
      const node = this.subQuestContainer.children[i]
      if (node) {
        node.active = true
        const label = node.getComponent(Label)
        if (label) {
          const statusIcon = sq.completed ? '[✓]' : '[ ]'
          label.string = `${statusIcon} ${sq.title} / ${sq.title_en}`
        }
      }
    }
  }
}
