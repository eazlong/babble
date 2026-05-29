'use client'

import { useState, useEffect } from 'react'
import Navbar from '../../components/Navbar'
import { getAuthToken, getParentId } from '../../lib/auth'

const API_BASE = process.env.NEXT_PUBLIC_API_URL || 'http://localhost:3001/api/v1'

interface ReportData {
  total_time_today?: number
  total_time_week?: number
  total_time_month?: number
  vocabulary_growth?: number
  cefr_level?: string
  cefr_progress?: number
  quests_completed?: number
}

export default function ReportsPage() {
  const [report, setReport] = useState<ReportData | null>(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState('')

  useEffect(() => {
    async function loadReports() {
      const token = getAuthToken()
      const parentId = getParentId()
      if (!token || !parentId) {
        setLoading(false)
        return
      }

      try {
        const res = await fetch(`${API_BASE}/parent/${parentId}/reports`, {
          headers: { Authorization: `Bearer ${token}` },
        })
        const data = await res.json()
        setReport(data)
      } catch {
        setError('Failed to load reports')
      } finally {
        setLoading(false)
      }
    }
    loadReports()
  }, [])

  if (loading) {
    return (
      <div className="min-h-screen bg-gray-50">
        <Navbar />
        <div className="flex items-center justify-center h-96">
          <p className="text-gray-500">Loading reports...</p>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-gray-50">
      <Navbar />
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <h1 className="text-2xl font-bold text-gray-800 mb-6">Learning Reports</h1>

        {error && (
          <div className="mb-6 p-4 bg-red-50 text-red-700 rounded-lg">
            {error}
          </div>
        )}

        {/* Time Stats */}
        <h2 className="text-lg font-semibold text-gray-700 mb-4">Study Time</h2>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-8">
          <div className="bg-white rounded-xl shadow-sm border border-gray-100 p-6">
            <div className="text-sm text-gray-500 mb-1">Today</div>
            <div className="text-3xl font-bold text-indigo-600">
              {report?.total_time_today ?? 0}
            </div>
            <div className="text-sm text-gray-400">minutes</div>
          </div>
          <div className="bg-white rounded-xl shadow-sm border border-gray-100 p-6">
            <div className="text-sm text-gray-500 mb-1">This Week</div>
            <div className="text-3xl font-bold text-green-600">
              {report?.total_time_week ?? 0}
            </div>
            <div className="text-sm text-gray-400">minutes</div>
          </div>
          <div className="bg-white rounded-xl shadow-sm border border-gray-100 p-6">
            <div className="text-sm text-gray-500 mb-1">This Month</div>
            <div className="text-3xl font-bold text-blue-600">
              {report?.total_time_month ?? 0}
            </div>
            <div className="text-sm text-gray-400">minutes</div>
          </div>
        </div>

        {/* Vocabulary & CEFR */}
        <h2 className="text-lg font-semibold text-gray-700 mb-4">Progress</h2>
        <div className="grid grid-cols-1 md:grid-cols-3 gap-4 mb-8">
          <div className="bg-white rounded-xl shadow-sm border border-gray-100 p-6">
            <div className="text-sm text-gray-500 mb-1">Vocabulary Growth</div>
            <div className="text-3xl font-bold text-purple-600">
              +{report?.vocabulary_growth ?? 0}
            </div>
            <div className="text-sm text-gray-400">new words</div>
          </div>
          <div className="bg-white rounded-xl shadow-sm border border-gray-100 p-6">
            <div className="text-sm text-gray-500 mb-1">CEFR Level</div>
            <div className="text-3xl font-bold text-amber-600">
              {report?.cefr_level ?? 'A1'}
            </div>
            {report?.cefr_progress != null && (
              <div className="mt-2 w-full bg-gray-200 rounded-full h-2">
                <div
                  className="bg-amber-500 h-2 rounded-full transition-all"
                  style={{ width: `${Math.min(100, Math.max(0, report.cefr_progress))}%` }}
                />
              </div>
            )}
            <div className="text-sm text-gray-400 mt-1">
              {report?.cefr_progress != null ? `${report.cefr_progress}% to next level` : ''}
            </div>
          </div>
          <div className="bg-white rounded-xl shadow-sm border border-gray-100 p-6">
            <div className="text-sm text-gray-500 mb-1">Quests Completed</div>
            <div className="text-3xl font-bold text-teal-600">
              {report?.quests_completed ?? 0}
            </div>
            <div className="text-sm text-gray-400">tasks done</div>
          </div>
        </div>
      </div>
    </div>
  )
}
