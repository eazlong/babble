export interface DropResult {
  item_id: string
  name: string
  item_type: string
  rarity: string
  thumbnail_ref: string
}

const REWARD_SERVICE_URL = process.env.REWARD_SERVICE_URL || 'http://localhost:8307'

function fallbackDrops(): Array<{ item_id: string; name: string }> {
  return [{ item_id: 'item_common_1', name: '铜币' }]
}

export async function getRewardDrop(
  questType: 'main' | 'sub' | 'daily',
  cefrLevel: string
): Promise<Array<{ item_id: string; name: string }>> {
  // reward-service uses 'side' not 'sub', normalize
  const serviceQuestType = questType === 'sub' ? 'side' : questType

  try {
    const res = await fetch(`${REWARD_SERVICE_URL}/api/v1/rewards/roll`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ quest_type: serviceQuestType, cefr_level: cefrLevel }),
      signal: AbortSignal.timeout(3000),
    })

    if (!res.ok) {
      console.warn('[reward-client] reward-service returned', res.status, '— using fallback')
      return fallbackDrops()
    }

    const drop: DropResult = await res.json()
    return [{ item_id: drop.item_id, name: drop.name }]
  } catch {
    console.warn('[reward-client] reward-service unreachable — using fallback')
    return fallbackDrops()
  }
}
