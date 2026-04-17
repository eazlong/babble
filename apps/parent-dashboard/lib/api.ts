const API_BASE = process.env.NEXT_PUBLIC_API_URL || 'https://api.linguaquest.com/api/v1'

export async function getParentDashboard(token: string, parentId: string) {
  const res = await fetch(`${API_BASE}/parent/${parentId}/dashboard`, {
    headers: { Authorization: `Bearer ${token}` }
  })
  return res.json()
}

export async function getChildProgress(token: string, childId: string) {
  const res = await fetch(`${API_BASE}/parent/children/${childId}/progress`, {
    headers: { Authorization: `Bearer ${token}` }
  })
  return res.json()
}

export async function updateTimeLimit(token: string, childId: string, minutes: number) {
  const res = await fetch(`${API_BASE}/parent/children/${childId}/time-limit`, {
    method: 'PUT',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify({ daily_time_limit_minutes: minutes })
  })
  return res.json()
}

export async function deleteChildData(token: string, childId: string) {
  const res = await fetch(`${API_BASE}/parent/children/${childId}/data`, {
    method: 'DELETE',
    headers: { Authorization: `Bearer ${token}` }
  })
  return res.json()
}
