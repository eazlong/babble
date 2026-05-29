'use client'

import { useEffect } from 'react'
import { useRouter } from 'next/navigation'
import { getAuthToken } from '../lib/auth'

export default function HomePage() {
  const router = useRouter()

  useEffect(() => {
    const token = getAuthToken()
    if (token) {
      router.push('/dashboard')
    } else {
      router.push('/login')
    }
  }, [router])

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50">
      <p className="text-gray-500">Redirecting...</p>
    </div>
  )
}
