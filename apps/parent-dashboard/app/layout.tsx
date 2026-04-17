import type { Metadata } from 'next'

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
      <body style={{ margin: 0, fontFamily: 'system-ui, sans-serif' }}>
        {children}
      </body>
    </html>
  )
}
