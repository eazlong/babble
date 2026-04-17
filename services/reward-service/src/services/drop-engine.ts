export type Rarity = 'common' | 'rare' | 'epic' | 'legendary' | 'limited'
export type ItemType = 'skin_protagonist' | 'skin_spirit' | 'decoration' | 'title' | 'effect'

export interface DropResult {
  item_id: string
  name: string
  item_type: ItemType
  rarity: Rarity
  thumbnail_ref: string
}

export class DropEngine {
  private dropRates: Record<Rarity, number> = {
    common: 70,
    rare: 20,
    epic: 8,
    legendary: 2,
    limited: 0
  }

  rollRarity(questType: 'main' | 'side' | 'daily'): Rarity {
    const roll = Math.random() * 100

    if (questType === 'main') {
      if (roll < 2) return 'legendary'
      if (roll < 10) return 'epic'
      if (roll < 30) return 'rare'
      return 'common'
    }

    if (roll < 2) return 'epic'
    if (roll < 22) return 'rare'
    return 'common'
  }

  async calculateDrop(
    userId: string,
    questType: 'main' | 'side' | 'daily',
    cefrLevel: string
  ): Promise<DropResult | null> {
    const rarity = this.rollRarity(questType)

    // MVP: Return a sample item
    const itemTypes: ItemType[] = ['skin_protagonist', 'decoration', 'title']
    const itemType = itemTypes[Math.floor(Math.random() * itemTypes.length)]

    return {
      item_id: `item_${rarity}_${Date.now()}`,
      name: `${rarity} ${itemType}`,
      item_type: itemType,
      rarity,
      thumbnail_ref: `items/${rarity}/${itemType}.png`
    }
  }
}
