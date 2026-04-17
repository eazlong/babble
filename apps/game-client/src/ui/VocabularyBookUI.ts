import { Label, Node } from 'cc'

export interface VocabularyEntry {
  word: string
  translation: string
  pronunciation: string
  example_sentence: string
  learned_at: string
}

export class VocabularyBookUI {
  private bookPanel: Node
  private entryList: Node
  private titleLabel: Label

  constructor(rootNode: Node) {
    this.bookPanel = rootNode.getChildByName('VocabBookPanel')!
    this.entryList = rootNode.getChildByName('EntryList')!
    this.titleLabel = rootNode.getChildByName('Title')!.getComponent(Label)!
  }

  openBook(entries: VocabularyEntry[]): void {
    this.titleLabel.string = `Vocabulary Book (${entries.length} words)`

    // Clear existing entries
    this.entryList.destroyAllChildren()

    for (const entry of entries) {
      const entryNode = new Node(`entry_${entry.word}`)
      this.entryList.addChild(entryNode)
    }

    this.bookPanel.active = true
  }

  close(): void {
    this.bookPanel.active = false
  }

  addEntry(entry: VocabularyEntry): void {
    const entryNode = new Node(`entry_${entry.word}`)
    this.entryList.addChild(entryNode)
  }
}
