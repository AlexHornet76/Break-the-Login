import { useState } from 'react'
import { Link, useNavigate, useLocation } from 'react-router-dom'
import { login } from '../api/auth'

export default function Login() {
  const [email, setEmail]       = useState('')
  const [password, setPassword] = useState('')
  const [error, setError]       = useState('')
  const [loading, setLoading]   = useState(false)
  const navigate  = useNavigate()
  const location  = useLocation()

  // Mesaj de succes daca venim de la Register
  const successMsg = location.state?.message

  async function handleSubmit(e) {
    e.preventDefault()
    setError('')
    setLoading(true)

    try {
      const res = await login(email, password)
      // Salvam token-ul si in localStorage — VULNERABIL (XSS il poate fura)
      localStorage.setItem('token', res.data.token)
      navigate('/dashboard')
    } catch (err) {
      // VULNERABIL: afisam exact mesajul de la server
      // "Utilizatorul nu exista" vs "Parola gresita" — user enumeration!
      const errorMessage = err.response?.data?.error || err.response?.data || 'Eroare la autentificare'
      setError(errorMessage)
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="page-center">
      <div className="card">
        <h2 style={{ marginBottom: 4 }}>Autentificare</h2>

        {successMsg && <div className="success">{successMsg}</div>}
        {error && <div className="error">{error}</div>}

        <form onSubmit={handleSubmit}>
          <div className="field">
            <label>Email</label>
            <input
              type="email"
              value={email}
              onChange={e => setEmail(e.target.value)}
              placeholder="angajat@authx.ro"
              required
            />
          </div>

          <div className="field">
            <label>Parola</label>
            <input
              type="password"
              value={password}
              onChange={e => setPassword(e.target.value)}
              placeholder="Parola ta"
              required
            />
          </div>

          <button className="btn" type="submit" disabled={loading}>
            {loading ? 'Se verifica...' : 'Autentifică-te'}
          </button>
        </form>

        <p className="text-center mt-16">
          <Link to="/forgot-password" className="link">Am uitat parola</Link>
        </p>
        <p className="text-center mt-8">
          Nu ai cont?{' '}
          <Link to="/register" className="link">Înregistrează-te</Link>
        </p>
      </div>
    </div>
  )
}