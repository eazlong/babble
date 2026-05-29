'use client'

import { useState, useEffect } from 'react'
import Navbar from '../../components/Navbar'
import { getAuthToken, getParentId } from '../../lib/auth'

const API_BASE = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:3001/api/v1'

const SCENES = [
  { key: 'SpiritForest', label: 'Spirit Forest', description: 'Explore the enchanted forest and learn nature vocabulary' },
  { key: 'SpellLibrary', label: 'Spell Library', description: 'Master magical spells with reading and writing exercises' },
  { key: 'RainbowGarden', label: 'Rainbow Garden', description: 'Discover colors and emotions through interactive play' },
]

const FILTER_LEVELS = [
  { value: 'relaxed', label: 'Relaxed', description: 'Minimal filtering, more creative freedom' },
  { value: 'moderate', label: 'Moderate', description: 'Balanced safety and learning experience' },
  { value: 'strict', label: 'Strict', description: 'Maximum content filtering and supervision' },
]

interface SceneToggle {
  enabled: boolean
}

interface ContentSettings {
  scenes: Record<string, SceneToggle>
  filter_level: string
}

export default function ContentControlPage() {
  const [scenes, setScenes] = useState<Record<string, boolean>>({
    SpiritForest: true,
    SpellLibrary: true,
    RainbowGarden: true,
  })
  const [filterLevel, setFilterLevel] = useState('moderate')
  const [saving, setSaving] = useState(false)
  const [saved, setSaved] = useState(false)
  const [loading, setLoading] = useState(true)
  const [childId, setChildId] = useState<string | null>(null)

  useEffect(() => {
    async function loadSettings() {
      const token = getAuthToken()
      const parentId = getParentId()
      if (!token || !parentId) {
        setLoading(false)
        return
      }

      // Try to get child ID from dashboard first
      try {
        const dashRes = await fetch(`${API_BASE}/parent/${parentId}/dashboard`, {
          headers: { Authorization: `Bearer ${token}` },
        })
        const dashData = await dashRes.json()
        if (dashData.children && dashData.children.length > 0) {
          const cid = dashData.children[0].child_id
          setChildId(cid)

          // Load content settings
          try {
            const settingsRes = await fetch(`${API_BASE}/parent/children/${cid}/content-settings`, {
              headers: { Authorization: `Bearer ${token}` },
            })
            const settingsData = await settingsRes.json()
            if (settingsData.scenes) {
              const sceneStates: Record<string, boolean> = {}
              for (const [key, val] of Object.entries(settingsData.scenes)) {
                sceneStates[key] = (val as SceneToggle).enabled
              }
              setScenes(sceneStates)
            }
            if (settingsData.filter_level) {
              setFilterLevel(settingsData.filter_level)
            }
          } catch {
            // Use defaults if settings not found
          }
        }
      } catch {
        // Use defaults
      }
      setLoading(false)
    }
    loadSettings()
  }, [])

  function toggleScene(key: string) {
    setScenes(prev => ({ ...prev, [key]: !prev[key] }))
  }

  async function handleSave() {
    const token = getAuthToken()
    if (!token || !childId) return

    setSaving(true)
    setSaved(false)

    const settings: ContentSettings = {
      scenes: {},
      filter_level: filterLevel,
    }
    for (const [key, enabled] of Object.entries(scenes)) {
      settings.scenes[key] = { enabled }
    }

    try {
      await fetch(`${API_BASE}/parent/children/${childId}/content-settings`, {
        method: 'PUT',
        headers: {
          Authorization: `Bearer ${token}`,
          'Content-Type': 'application/json',
        },
        body: JSON.stringify(settings),
      })
      setSaved(true)
      setTimeout(() => setSaved(false), 3000)
    } catch {
      alert('Failed to save content settings.')
    } finally {
      setSaving(false)
    }
  }

  if (loading) {
    return (
      <div className="min-h-screen bg-gray-50">
        <Navbar />
        <div className="flex items-center justify-center h-96">
          <p className="text-gray-500">Loading content settings...</p>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <Navbar />
      <div className="max-w-3xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <h1 className="text-2xl font-bold text-gray-800 mb-6">Content Control</h1>

        {/* Scene Toggles */}
        <div className="bg-white rounded-xl shadow-sm border border-gray-100 p-6 mb-6">
          <h2 className="text-lg font-semibold text-gray-700 mb-4">Scene Access</h2>
          <div className="space-y-4">
            {SCENES.map(scene => (
              <div key={scene.key} className="flex items-center justify-between py-3 border-b border-gray-100 last:border-0">
                <div>
                  <div className="font-medium text-gray-800">{scene.label}</div>
                  <div className="text-sm text-gray-500">{scene.description}</div>
                </div>
                <button
                  onClick={() => toggleScene(scene.key)}
                  className={`relative inline-flex h-7 w-12 items-center rounded-full transition-colors ${
                    scenes[scene.key] ? 'bg-indigo-600' : 'bg-gray-300'
                  }`}
                >
                  <span
                    className={`inline-block h-5 w-5 rounded-full bg-white shadow-sm transition-transform ${
                      scenes[scene.key] ? 'translate-x-6' : 'translate-x-1'
                    }`}
                  />
                </button>
              </div>
            ))}
          </div>
        </div>

        {/* Filter Level */}
        <div className="bg-white rounded-xl shadow-sm border border-gray-100 p-6 mb-6">
          <h2 className="text-lg font-semibold text-gray-700 mb-4">Content Filter Level</h2>
          <div className="space-y-3">
            {FILTER_LEVELS.map(level => (
              <label
                key={level.value}
                className={`flex items-center justify-between p-4 rounded-lg border-2 cursor-pointer transition-colors ${
                  filterLevel === level.value
                    ? 'border-indigo-500 bg-indigo-50'
                    : 'border-gray-200 hover:border-gray-300'
                }`}
              >
                <div className="flex items-center gap-3">
                  <input
                    type="radio"
                    name="filterLevel"
                    value={level.value}
                    checked={filterLevel === level.value}
                    onChange={() => setFilterLevel(level.value)}
                    className="h-4 w-4 text-indigo-600 focus:ring-indigo-500"
                  />
                  <div>
                    <div className="font-medium text-gray-800">{level.label}</div>
                    <div className="text-sm text-gray-500">{level.description}</div>
                  </div>
                </div>
              </label>
            ))}
          </div>
        </div>

        {/* Save Button */}
        <div className="flex items-center gap-4">
          <button
            onClick={handleSave}
            disabled={saving}
            className="bg-indigo-600 text-white font-medium px-6 py-2.5 rounded-lg hover:bg-indigo-700 transition-colors disabled:opacity-60 disabled:cursor-not-allowed"
          >
            {saving ? 'Saving...' : 'Save Settings'}
          </button>
          {saved && (
            <span className="text-green-600 text-sm font-medium">Settings saved!</span>
          )}
        </div>
      </div>
    </div>
  )
}
