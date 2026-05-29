'use client'

import { useEffect, useState } from 'react'
import { useRouter, usePathname } from 'next/navigation'
import { getAuthToken } from '../lib/auth'

export default function AuthGuard({ children }: { children: React.ReactNode }) {
  const router = useRouter()
  const pathname = usePathname()
  const [checking, setChecking] = useState(true)

  useEffect(() => {
    // Don't guard /login and /register pages
    if (pathname === '/login' || pathname === '/register') {
      setChecking(false)
      return
    }

    const token = getAuthToken()
    if (!token) {
      router.push('/login')
    } else {
      setChecking(false)
    }
  }, [pathname, router])

  if (checking) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <div className="text-gray-500">Loading...</div>
      </div>
    )
  }

  return <>{children}</>
}
