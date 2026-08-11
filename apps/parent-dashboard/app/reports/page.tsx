'use client'

import { useState, useEffect } from 'react'
import Navbar from '../../components/Navbar'
import { getAuthToken, getParentId } from '../../lib/auth'
import { getReports, getDiagnosis } from '../../lib/api'

interface ReportData {
  total_time_today?: number
  total_time_week?: number
  total_time_month?: number
  vocabulary_growth?: number
  cefr_level?: string
  cefr_progress?: number
  quests_completed?: number
}

// 家长可见诊断字段（CONTEXT 家长可见诊断 / D1 裁剪）
interface DiagnosisItem {
  knowledge_item_id: string
  item_type: string
  mastery_band: string
  assessment_count: number
  last_assessed_at: string
}
interface DiagnosisData {
  child_id: string
  summary?: {
    total_items: number
    mastered_count: number
    partial_count: number
    unmastered_count: number
  }
  mastery_breakdown?: {
    mastered: DiagnosisItem[]
    partial: DiagnosisItem[]
    unmastered: DiagnosisItem[]
  }
  weak_items_ranked?: DiagnosisItem[]
}
interface DiagnosisResponse {
  diagnosis: DiagnosisData | null
  status: string
}

const TYPE_LABELS: Record<string, string> = {
  word: '单词',
  grammar: '语法',
  reading: '阅读技能',
  expr: '表达目标句',
}
const BAND_LABELS: Record<string, string> = {
  mastered: '掌握',
  partial: '部分掌握',
  unmastered: '未掌握',
}

// 去前缀 slug：word:apple → apple，expr:her_name_is_aling → her_name_is_aling
function slugOf(id: string): string {
  const idx = id.indexOf(':')
  return idx >= 0 ? id.slice(idx + 1) : id
}

export default function ReportsPage() {
  const [report, setReport] = useState<ReportData | null>(null)
  const [diagnosis, setDiagnosis] = useState<DiagnosisData | null>(null)
  const [diagStatus, setDiagStatus] = useState<string>('loading')
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

      // F2：运营指标与诊断独立请求，并行拉取，故障域隔离
      const reportsP = getReports(token, parentId).catch(() => {
        setError('Failed to load reports')
        return null
      })
      const diagP = getDiagnosis(token, parentId)
        .then((d: DiagnosisResponse) => {
          setDiagnosis(d.diagnosis)
          setDiagStatus(d.status)
        })
        .catch(() => setDiagStatus('generating'))

      const [reportData] = await Promise.all([reportsP, diagP])
      if (reportData) setReport(reportData)
      setLoading(false)
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

  // 诊断分组：按 item_type 聚合所有条目
  const allItems: DiagnosisItem[] = diagnosis?.mastery_breakdown
    ? [
        ...diagnosis.mastery_breakdown.mastered,
        ...diagnosis.mastery_breakdown.partial,
        ...diagnosis.mastery_breakdown.unmastered,
      ]
    : []
  const byType: Record<string, DiagnosisItem[]> = {}
  for (const item of allItems) {
    if (!byType[item.item_type]) byType[item.item_type] = []
    byType[item.item_type].push(item)
  }
  const weak = diagnosis?.weak_items_ranked ?? []

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

        {/* 学习诊断（主线，B）*/}
        <h2 className="text-lg font-semibold text-gray-700 mb-4">学习诊断</h2>
        {diagStatus === 'ok' && diagnosis ? (
          <div className="space-y-6 mb-8">
            {/* 薄弱项置顶 */}
            {weak.length > 0 && (
              <div className="bg-white rounded-xl shadow-sm border border-gray-100 p-6">
                <h3 className="font-semibold text-gray-700 mb-3">需要关注</h3>
                <div className="flex flex-wrap gap-2">
                  {weak.slice(0, 8).map(item => (
                    <span
                      key={item.knowledge_item_id}
                      className="inline-flex items-center gap-1 px-3 py-1 rounded-full bg-amber-50 text-amber-700 text-sm border border-amber-200"
                    >
                      {slugOf(item.knowledge_item_id)}
                      <span className="text-amber-400">·</span>
                      <span className="text-xs">{BAND_LABELS[item.mastery_band] ?? item.mastery_band}</span>
                    </span>
                  ))}
                </div>
                <p className="text-xs text-gray-400 mt-2">按薄弱程度排序</p>
              </div>
            )}

            {/* 总览计数 */}
            {diagnosis.summary && (
              <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                <DiagStat label="总条目" value={diagnosis.summary.total_items} color="text-gray-800" />
                <DiagStat label="掌握" value={diagnosis.summary.mastered_count} color="text-green-600" />
                <DiagStat label="部分掌握" value={diagnosis.summary.partial_count} color="text-amber-600" />
                <DiagStat label="未掌握" value={diagnosis.summary.unmastered_count} color="text-red-600" />
              </div>
            )}

            {/* 按类型分组（I3）*/}
            {Object.entries(byType).map(([type, items]) => (
              <div key={type} className="bg-white rounded-xl shadow-sm border border-gray-100 p-6">
                <h3 className="font-semibold text-gray-700 mb-3">
                  {TYPE_LABELS[type] ?? type}
                  <span className="ml-2 text-sm text-gray-400">{items.length} 项</span>
                </h3>
                <div className="flex flex-wrap gap-2">
                  {items.map(item => (
                    <span
                      key={item.knowledge_item_id}
                      className={`inline-flex items-center gap-1 px-3 py-1 rounded-full text-sm border ${
                        item.mastery_band === 'mastered'
                          ? 'bg-green-50 text-green-700 border-green-200'
                          : item.mastery_band === 'partial'
                          ? 'bg-amber-50 text-amber-700 border-amber-200'
                          : 'bg-red-50 text-red-700 border-red-200'
                      }`}
                    >
                      {slugOf(item.knowledge_item_id)}
                    </span>
                  ))}
                </div>
              </div>
            ))}

            <p className="text-xs text-gray-400">
              以下为孩子学习内容条目。如对某项含义有疑问，可联系老师。
            </p>
          </div>
        ) : (
          <div className="bg-white rounded-xl shadow-sm border border-gray-100 p-8 text-center mb-8">
            <p className="text-gray-500">
              {diagStatus === 'no_child' ? '尚未关联孩子账户。' : '诊断生成中...'}
            </p>
          </div>
        )}

        {/* 运营指标（辅，A）*/}
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

function DiagStat({ label, value, color }: { label: string; value: number; color: string }) {
  return (
    <div className="bg-white rounded-xl shadow-sm border border-gray-100 p-6 text-center">
      <div className={`text-3xl font-bold ${color}`}>{value}</div>
      <div className="text-sm text-gray-500 mt-1">{label}</div>
    </div>
  )
}
