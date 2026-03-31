import { useState, useEffect } from 'react'
import { useNavigate } from 'react-router-dom'
import { getMe, logout } from '../api/auth'

export default function Dashboard() {
  const [user, setUser] = useState(null)
  const navigate = useNavigate()

  useEffect(() => {
    getMe().then(res => setUser(res.data))
  }, [])

  async function handleLogout() {
    await logout()
    navigate('/login')
  }

  function goTickets() {
    navigate('/tickets')
  }

  return (
    <div className="page-center">
      <div className="card">
        <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', marginBottom: 24 }}>
          <h2>Dashboard</h2>

          <div style={{ display: 'flex', gap: 8 }}>
            <button
              onClick={goTickets}
              style={{ background: 'none', border: '1px solid #ddd', borderRadius: 6, padding: '6px 14px', cursor: 'pointer', fontSize: 13 }}
            >
              Tickets
            </button>

            <button
              onClick={handleLogout}
              style={{ background: 'none', border: '1px solid #ddd', borderRadius: 6, padding: '6px 14px', cursor: 'pointer', fontSize: 13 }}
            >
              Logout
            </button>
          </div>
        </div>

        {user ? (
          <>
            <div className="success">
              Autentificat ca: <strong>{user.email}</strong>
            </div>

            <div style={{ background: '#f8fafc', borderRadius: 8, padding: 16, marginTop: 16 }}>
              <p style={{ fontSize: 13, color: '#666', marginBottom: 8 }}>Date sesiune din cookie:</p>
              <code style={{ fontSize: 12 }}>
                user_id: {user.user_id}<br />
                email: {user.email}
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