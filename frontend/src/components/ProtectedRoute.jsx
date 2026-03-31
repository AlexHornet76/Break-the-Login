import { useState, useEffect } from 'react'
import { Navigate } from 'react-router-dom'
import { getMe } from '../api/auth'

export default function ProtectedRoute({ children }) {
  const [status, setStatus] = useState('loading') // loading | ok | denied

  useEffect(() => {
    getMe()
      .then(() => setStatus('ok'))
      .catch(() => setStatus('denied'))
  }, [])

  if (status === 'loading') return <p style={{ padding: 24 }}>Se verifica sesiunea...</p>
  if (status === 'denied') return <Navigate to="/login" />
  return children
}