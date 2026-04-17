'use client'

import { useState, useEffect } from 'react'
import { getParentDashboard, getChildProgress, updateTimeLimit, deleteChildData } from '../../lib/api'
import { getAuthToken, getParentId } from '../../lib/auth'

interface ChildData {
  child_id: string
  display_name: string
  total_time_today: number
  daily_time_limit_minutes: number
  vocabulary_count?: number
  cefr_level?: string
  quests_completed?: number
}

export default function DashboardPage() {
  const [children, setChildren] = useState<ChildData[]>([])
  const [loading, setLoading] = useState(true)

  useEffect(() => {
    async function loadDashboard() {
      const token = getAuthToken()
      const parentId = getParentId()
      if (!token || !parentId) {
        setLoading(false)
        return
      }
      try {
        const data = await getParentDashboard(token, parentId)
        setChildren(data.children || [])
      } catch {
        setChildren([])
      }
      setLoading(false)
    }
    loadDashboard()
  }, [])

  if (loading) return <div>Loading...</div>

  return (
    <main className="min-h-screen bg-gray-50 p-6">
      <h1 className="text-2xl font-bold mb-6">Parent Dashboard</h1>

      {children.map(child => (
        <ChildCard key={child.child_id} child={child} />
      ))}

      {children.length === 0 && (
        <p className="text-gray-500">No children linked to this account.</p>
      )}
    </main>
  )
}

function ChildCard({ child }: { child: ChildData }) {
  return (
    <div className="bg-white rounded-lg shadow p-6 mb-4">
      <div className="flex justify-between items-center mb-4">
        <h2 className="text-xl font-semibold">{child.display_name}</h2>
        <span className="text-sm text-gray-500">
          Time today: {child.total_time_today}/{child.daily_time_limit_minutes} min
        </span>
      </div>

      <div className="grid grid-cols-3 gap-4">
        <StatCard label="Vocabulary" value={child.vocabulary_count || 0} />
        <StatCard label="CEFR Level" value={child.cefr_level || 'A1'} />
        <StatCard label="Quests Done" value={child.quests_completed || 0} />
      </div>

      <div className="mt-4 flex gap-2">
        <a href={`/settings?child=${child.child_id}`} style={{ padding: '8px 16px', background: '#e5e7eb', borderRadius: '6px', textDecoration: 'none', color: '#374151' }}>
          Settings
        </a>
        <button
          style={{ padding: '8px 16px', background: '#ef4444', color: '#fff', border: 'none', borderRadius: '6px', cursor: 'pointer' }}
          onClick={() => handleDeleteData(child.child_id)}
        >
          Delete All Data
        </button>
      </div>
    </div>
  )
}

function StatCard({ label, value }: { label: string; value: string | number }) {
  return (
    <div style={{ background: '#f3f4f6', borderRadius: '8px', padding: '12px', textAlign: 'center' }}>
      <div style={{ fontSize: '1.5rem', fontWeight: 'bold' }}>{value}</div>
      <div style={{ fontSize: '0.875rem', color: '#6b7280' }}>{label}</div>
    </div>
  )
}

async function handleDeleteData(childId: string) {
  const confirmed = confirm('Are you sure you want to delete all data for this child? This action cannot be undone.')
  if (!confirmed) return

  const token = getAuthToken()
  if (!token) return

  try {
    await deleteChildData(token, childId)
    alert('Data deleted successfully.')
    window.location.reload()
  } catch {
    alert('Failed to delete data.')
  }
}
