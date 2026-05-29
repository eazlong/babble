'use client'

import { useState, useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { getParentDashboard, getChildProgress, updateTimeLimit, deleteChildData } from '../../lib/api'
import { getAuthToken, getParentId } from '../../lib/auth'
import Navbar from '../../components/Navbar'

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
  const router = useRouter()
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

  if (loading) return (
    <div className="min-h-screen bg-gray-50">
      <Navbar />
      <div className="flex items-center justify-center h-96">
        <p className="text-gray-500">Loading...</p>
      </div>
    </div>
  )

  return (
    <div className="min-h-screen bg-gray-50">
      <Navbar />
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <h1 className="text-2xl font-bold text-gray-800 mb-6">Parent Dashboard</h1>

        {children.map(child => (
          <ChildCard key={child.child_id} child={child} />
        ))}

        {children.length === 0 && (
          <div className="bg-white rounded-xl shadow-sm border border-gray-100 p-8 text-center">
            <p className="text-gray-500">No children linked to this account.</p>
          </div>
        )}
      </div>
    </div>
  )
}

function ChildCard({ child }: { child: ChildData }) {
  return (
    <div className="bg-white rounded-xl shadow-sm border border-gray-100 p-6 mb-4">
      <div className="flex justify-between items-center mb-4">
        <h2 className="text-xl font-semibold text-gray-800">{child.display_name}</h2>
        <span className="text-sm text-gray-500">
          Time today: {child.total_time_today}/{child.daily_time_limit_minutes} min
        </span>
      </div>

      <div className="grid grid-cols-3 gap-4 mb-4">
        <StatCard label="Vocabulary" value={child.vocabulary_count || 0} />
        <StatCard label="CEFR Level" value={child.cefr_level || 'A1'} />
        <StatCard label="Quests Done" value={child.quests_completed || 0} />
      </div>

      <div className="flex gap-2">
        <a
          href={`/settings?child=${child.child_id}`}
          className="px-4 py-2 bg-gray-100 text-gray-700 rounded-lg hover:bg-gray-200 transition-colors text-sm font-medium"
        >
          Settings
        </a>
        <button
          className="px-4 py-2 bg-red-500 text-white rounded-lg hover:bg-red-600 transition-colors text-sm font-medium"
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
    <div className="bg-gray-50 rounded-lg p-4 text-center">
      <div className="text-2xl font-bold text-gray-800">{value}</div>
      <div className="text-sm text-gray-500">{label}</div>
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
