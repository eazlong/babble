'use client'

import { useRouter } from 'next/navigation'
import { clearAuth } from '../lib/auth'
import Link from 'next/link'
import { usePathname } from 'next/navigation'

const navLinks = [
  { label: 'Dashboard', href: '/dashboard' },
  { label: 'Reports', href: '/reports' },
  { label: 'Content Control', href: '/content-control' },
  { label: 'Settings', href: '/settings' },
]

export default function Navbar() {
  const router = useRouter()
  const pathname = usePathname()

  function handleLogout() {
    clearAuth()
    router.push('/login')
  }

  return (
    <nav className="bg-white shadow-sm border-b border-gray-200">
      <div className="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8">
        <div className="flex justify-between items-center h-16">
          {/* Left: Logo */}
          <div className="flex-shrink-0">
            <Link href="/dashboard" className="flex flex-col">
              <span className="text-xl font-bold text-indigo-600">LinguaQuest</span>
              <span className="text-xs text-gray-500 -mt-1">Parent Dashboard</span>
            </Link>
          </div>

          {/* Center: Navigation Links */}
          <div className="hidden md:flex items-center space-x-6">
            {navLinks.map(link => (
              <Link
                key={link.href}
                href={link.href}
                className={`text-sm font-medium px-3 py-2 rounded-md transition-colors ${
                  pathname === link.href
                    ? 'bg-indigo-50 text-indigo-700'
                    : 'text-gray-600 hover:text-indigo-600 hover:bg-gray-50'
                }`}
              >
                {link.label}
              </Link>
            ))}
          </div>

          {/* Right: Logout Button */}
          <div>
            <button
              onClick={handleLogout}
              className="text-sm font-medium text-gray-600 hover:text-red-600 px-3 py-2 rounded-md hover:bg-red-50 transition-colors"
            >
              Logout
            </button>
          </div>
        </div>
      </div>

      {/* Mobile nav */}
      <div className="md:hidden border-t border-gray-200 px-4 py-2 flex space-x-2 overflow-x-auto">
        {navLinks.map(link => (
          <Link
            key={link.href}
            href={link.href}
            className={`text-xs font-medium px-3 py-1.5 rounded-md whitespace-nowrap transition-colors ${
              pathname === link.href
                ? 'bg-indigo-50 text-indigo-700'
                : 'text-gray-600 hover:text-indigo-600'
            }`}
          >
            {link.label}
          </Link>
        ))}
      </div>
    </nav>
  )
}
