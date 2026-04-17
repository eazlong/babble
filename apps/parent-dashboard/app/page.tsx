export default function HomePage() {
  return (
    <main style={{ minHeight: '100vh', display: 'flex', flexDirection: 'column', alignItems: 'center', justifyContent: 'center', background: '#f5f5f5' }}>
      <h1 style={{ fontSize: '2rem', marginBottom: '1rem' }}>LinguaQuest</h1>
      <p style={{ fontSize: '1.2rem', color: '#666', marginBottom: '2rem' }}>Parent Dashboard</p>
      <a
        href="/dashboard"
        style={{
          padding: '12px 32px',
          background: '#4f46e5',
          color: '#fff',
          textDecoration: 'none',
          borderRadius: '8px',
          fontSize: '1rem'
        }}
      >
        Go to Dashboard
      </a>
    </main>
  )
}
