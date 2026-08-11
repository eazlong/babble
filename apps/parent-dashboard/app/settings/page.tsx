'use client'

import { useState } from 'react'
import { useRouter } from 'next/navigation'
import { updateTimeLimit } from '../../lib/api'
import { getAuthToken } from '../../lib/auth'
import Navbar from '../../components/Navbar'

export default function SettingsPage() {
  const router = useRouter()
  const [timeLimit, setTimeLimit] = useState(60)
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)

  async function handleSave() {
    const token = getAuthToken()
    if (!token) return

    const params = new URLSearchParams(window.location.search)
    const childId = params.get('child')
    if (!childId) return

    setSaving(true)
    try {
      await updateTimeLimit(token, childId, timeLimit)
      setSaved(true)
    } catch {
      alert('Failed to save settings.')
    }
    setSaving(false)
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <Navbar />
      <div className="max-w-3xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <h1 className="text-2xl font-bold text-gray-800 mb-6">Child Settings</h1>

        <div className="bg-white rounded-xl shadow-sm border border-gray-100 p-6 max-w-md">
          <label className="block mb-4">
            <span className="text-sm font-medium text-gray-700 block mb-1">Daily Time Limit (minutes)</span>
            <input
              type="number"
              min={5}
              max={180}
              value={timeLimit}
              onChange={e => setTimeLimit(parseInt(e.target.value, 10))}
              className="w-full rounded-lg border border-gray-300 px-4 py-2.5 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:border-transparent"
            />
            <span className="text-xs text-gray-400">此设置暂不强制执行，仅作记录。</span>
          </label>

          <button
            onClick={handleSave}
            disabled={saving}
            className="px-6 py-2.5 bg-indigo-600 text-white font-medium rounded-lg hover:bg-indigo-700 transition-colors disabled:opacity-60 disabled:cursor-not-allowed"
          >
            {saving ? 'Saving...' : 'Save'}
          </button>

          {saved && <p className="mt-2 text-green-600 text-sm">Settings saved!</p>}

          <button
            onClick={() => router.push('/dashboard')}
            className="block mt-4 text-indigo-600 hover:text-indigo-700 font-medium text-sm"
          >
            ← Back to Dashboard
          </button>
        </div>
      </div>
    </div>
  )
}
