import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { getMe, logout } from '../api/auth'

export default function Dashboard() {
  const [user, setUser]     = useState(null)
  const navigate            = useNavigate()

  useEffect(() => {
    getMe().then(res => setUser(res.data))
  }, [])

  async function handleLogout() {
    await logout()
    localStorage.removeItem('token')
    navigate('/login')
  }

  return (
    <div className="page-center">
      <div className="card">
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 24 }}>
          <h2>Dashboard</h2>
          <button
            onClick={handleLogout}
            style={{ background: 'none', border: '1px solid #ddd', borderRadius: 6, padding: '6px 14px', cursor: 'pointer', fontSize: 13 }}
          >
            Logout
          </button>
        </div>

        {user ? (
          <>
            <div className="success">
              Autentificat ca: <strong>{user.email}</strong>
            </div>

            <div style={{ background: '#f8fafc', borderRadius: 8, padding: 16, marginTop: 16 }}>
              <p style={{ fontSize: 13, color: '#666', marginBottom: 8 }}>Date sesiune (din JWT):</p>
              <code style={{ fontSize: 12 }}>
                user_id: {user.user_id}<br />
                email: {user.email}
              </code>
            </div>

            <div className="vuln-badge" style={{ marginTop: 16 }}>
               token-ul JWT e și în localStorage (XSS îl poate fura)
            </div>

            <div style={{ marginTop: 12, background: '#fff7ed', borderRadius: 8, padding: 12 }}>
              <p style={{ fontSize: 11, color: '#c2410c', marginBottom: 6 }}>Token din localStorage (atacabil via XSS):</p>
              <code style={{ fontSize: 10, wordBreak: 'break-all', color: '#7c3aed' }}>
                {localStorage.getItem('token')}
              </code>
            </div>
          </>
        ) : (
          <p>Se încarcă...</p>
        )}
      </div>
    </div>
  )
}