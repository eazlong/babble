export interface DropResult {
  item_id: string
  name: string
  item_type: string
  rarity: string
  thumbnail_ref: string
}

export interface UserRewardState {
  user_id: string
  xp_total: number
  xp_level: number
  badges: string[]
  unlocked_areas: string[]
  grant_count: number
}

export interface AchievementUnlock {
  achievement: {
    id: string
    name: string
    description: string
  }
  reward_grant_id: string
  reward: Record<string, unknown>
}

export interface QuestCompleteResponse {
  drop: DropResult | null
  user_state: UserRewardState
  xp_result: { old_level: number; new_level: number; leveled_up: boolean }
  achievements_unlocked: AchievementUnlock[]
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

/** Complete a quest — grants XP, rolls drop, and checks achievements. */
export async function completeQuest(
  userId: string,
  questId: string,
  questType: 'main' | 'sub' | 'daily',
  cefrLevel: string
): Promise<QuestCompleteResponse | null> {
  const serviceQuestType = questType === 'sub' ? 'side' : questType

  try {
    const res = await fetch(`${REWARD_SERVICE_URL}/api/v1/rewards/quest-complete`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        user_id: userId,
        quest_id: questId,
        quest_type: serviceQuestType,
        cefr_level: cefrLevel,
      }),
      signal: AbortSignal.timeout(5000),
    })

    if (!res.ok) {
      console.warn('[reward-client] quest-complete failed:', res.status)
      return null
    }

    return await res.json()
  } catch (err) {
    console.warn('[reward-client] quest-complete unreachable:', err)
    return null
  }
}

/** Get user reward state. */
export async function getUserState(userId: string): Promise<UserRewardState | null> {
  try {
    const res = await fetch(`${REWARD_SERVICE_URL}/api/v1/rewards/state/${userId}`, {
      signal: AbortSignal.timeout(3000),
    })

    if (!res.ok) return null
    return await res.json()
  } catch {
    return null
  }
}

/** Grant XP directly (e.g. from assessment). */
export async function grantXP(
  userId: string,
  amount: number,
  source = 'assessment'
): Promise<{ user_state: UserRewardState; achievements_unlocked: AchievementUnlock[] } | null> {
  try {
    const res = await fetch(`${REWARD_SERVICE_URL}/api/v1/rewards/grant-xp`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ user_id: userId, amount, source }),
      signal: AbortSignal.timeout(3000),
    })

    if (!res.ok) return null
    return await res.json()
  } catch {
    return null
  }
}
