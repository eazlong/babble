/**
 * DialogueBox - NPC dialogue bubble renderer with typing animation.
 */

import { _decorator, Component, Node, Label } from 'cc'

const { ccclass, property } = _decorator

@ccclass('DialogueBox')
export class DialogueBox extends Component {
  @property(Label) npcNameLabel: Label | null = null
  @property(Label) dialogueText: Label | null = null
  @property(Node) continueIndicator: Node | null = null
  @property({ tooltip: 'Characters per tick for typing animation' })
  typingSpeed: number = 3

  private isTyping: boolean = false
  private fullText: string = ''
  private currentIndex: number = 0
  private typingInterval: number = 0

  start() {
    this.node.active = false
    this.node.on(Node.EventType.TOUCH_END, this.onTap, this)
  }

  show(npcName: string, text: string): void {
    this.node.active = true
    this.fullText = text
    this.currentIndex = 0

    if (this.npcNameLabel) {
      this.npcNameLabel.string = npcName
    }

    this.continueIndicator?.active = false
    this.startTyping()
  }

  hide(): void {
    this.node.active = false
    this.isTyping = false
    this.stopTypingTimer()
  }

  onTap(): void {
    if (this.isTyping) {
      // Skip to end
      this.stopTypingTimer()
      this.isTyping = false
      if (this.dialogueText) {
        this.dialogueText.string = this.fullText
      }
      this.continueIndicator?.active = true
    } else {
      // Close dialogue
      this.hide()
    }
  }

  private startTyping(): void {
    if (!this.dialogueText) return
    this.isTyping = true
    this.dialogueText.string = ''

    const tick = () => {
      if (!this.isTyping) return
      this.currentIndex++
      if (this.dialogueText) {
        this.dialogueText.string = this.fullText.substring(0, this.currentIndex)
      }
      if (this.currentIndex >= this.fullText.length) {
        this.isTyping = false
        this.continueIndicator?.active = true
      } else {
        this.typingInterval = setTimeout(tick, 1000 / this.typingSpeed)
      }
    }

    tick()
  }

  private stopTypingTimer(): void {
    if (this.typingInterval) {
      clearTimeout(this.typingInterval)
    }
  }
}
