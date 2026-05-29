const API_BASE = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:3001/api/v1'

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

export async function login(email: string, password: string) {
  const res = await fetch(`${API_BASE}/auth/login`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password })
  })
  return res.json()
}

export async function register(email: string, password: string, childName: string) {
  const res = await fetch(`${API_BASE}/auth/register`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ email, password, child_name: childName })
  })
  return res.json()
}

export async function getReports(token: string, parentId: string) {
  const res = await fetch(`${API_BASE}/parent/${parentId}/reports`, {
    headers: { Authorization: `Bearer ${token}` }
  })
  return res.json()
}

export async function getContentSettings(token: string, childId: string) {
  const res = await fetch(`${API_BASE}/parent/children/${childId}/content-settings`, {
    headers: { Authorization: `Bearer ${token}` }
  })
  return res.json()
}

export async function updateContentSettings(token: string, childId: string, settings: any) {
  const res = await fetch(`${API_BASE}/parent/children/${childId}/content-settings`, {
    method: 'PUT',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(settings)
  })
  return res.json()
}
