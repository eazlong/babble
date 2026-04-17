'use client'

import { useState } from 'react'
import { updateTimeLimit } from '../../lib/api'
import { getAuthToken } from '../../lib/auth'

export default function SettingsPage() {
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
    <main className="min-h-screen bg-gray-50 p-6">
      <h1 className="text-2xl font-bold mb-6">Child Settings</h1>

      <div className="bg-white rounded-lg shadow p-6 max-w-md">
        <label className="block mb-4">
          <span className="text-sm font-medium text-gray-700">Daily Time Limit (minutes)</span>
          <input
            type="number"
            min={5}
            max={180}
            value={timeLimit}
            onChange={e => setTimeLimit(parseInt(e.target.value, 10))}
            className="mt-1 block w-full rounded-md border-gray-300 shadow-sm border p-2"
          />
        </label>

        <button
          onClick={handleSave}
          disabled={saving}
          style={{
            padding: '8px 24px',
            background: '#4f46e5',
            color: '#fff',
            border: 'none',
            borderRadius: '6px',
            cursor: saving ? 'not-allowed' : 'pointer',
            opacity: saving ? 0.6 : 1
          }}
        >
          {saving ? 'Saving...' : 'Save'}
        </button>

        {saved && <p className="mt-2 text-green-600">Settings saved!</p>}

        <a href="/dashboard" className="block mt-4 text-indigo-600">
          ← Back to Dashboard
        </a>
      </div>
    </main>
  )
}
