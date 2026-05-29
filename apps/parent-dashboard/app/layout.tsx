import type { Metadata } from 'next'
import AuthGuard from '../components/AuthGuard'
import './globals.css'

export const metadata: Metadata = {
  title: 'LinguaQuest - Parent Dashboard',
  description: 'Monitor and manage your child\'s language learning progress'
}

export default function RootLayout({
  children
}: {
  children: React.ReactNode
}) {
  return (
    <html lang="zh-CN">
      <body className="min-h-screen bg-gray-50">
        <AuthGuard>{children}</AuthGuard>
      </body>
    </html>
  )
}
