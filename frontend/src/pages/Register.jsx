import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { register } from '../api/auth'

export default function Register() {
  const [email, setEmail]       = useState('')
  const [password, setPassword] = useState('')
  const [error, setError]       = useState('')
  const [loading, setLoading]   = useState(false)
  const navigate = useNavigate()

  async function handleSubmit(e) {
    e.preventDefault()
    setError('')
    setLoading(true)

    try {
      await register(email, password)
      navigate('/login', { state: { message: 'Cont creat! Te poți autentifica.' } })
    } catch (err) {
      // VULNERABIL: afisam exact eroarea de la server
      // Atacatorul stie daca emailul e deja luat
      setError(err.response?.data || 'Eroare la inregistrare')
    } finally {
      setLoading(false)
    }
  }

  return (
    <div className="page-center">
      <div className="card">
        <h2 style={{ marginBottom: 4 }}>Fa-ti cont</h2>

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
              placeholder="parola"
            />
            
          </div>

          <button className="btn" type="submit" disabled={loading}>
            {loading ? 'Se creeaza...' : 'Înregistrare'}
          </button>
        </form>

        <p className="text-center mt-16">
          Ai deja cont?{' '}
          <Link to="/login" className="link">Autentifică-te</Link>
        </p>
      </div>
    </div>
  )
}