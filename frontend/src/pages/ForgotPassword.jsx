import { useState } from 'react'
import { Link } from 'react-router-dom'
import { forgotPassword, resetPassword } from '../api/auth'

export default function ForgotPassword() {
  const [email, setEmail]       = useState('')
  const [token, setToken]       = useState('')
  const [password, setPassword] = useState('')
  const [step, setStep]         = useState(1) // 1 = cere email, 2 = introdu token+parolă
  const [message, setMessage]   = useState('')
  const [error, setError]       = useState('')
  const [resetToken, setResetToken] = useState('') // token returnat de server (vulnerabil)

  async function handleForgot(e) {
    e.preventDefault()
    setError('')
    try {
      const res = await forgotPassword(email)
      // VULNERABIL: server-ul returnează token-ul direct în response
      setResetToken(res.data.reset_token)
      setToken(res.data.reset_token) // FIX: Auto-completează câmpul token
      setMessage(res.data.message)
      setStep(2)
    } catch (err) {
      // FIX: Convertim eroarea la string
      const errorMsg = err.response?.data?.error || err.response?.data || 'Eroare'
      setError(typeof errorMsg === 'string' ? errorMsg : JSON.stringify(errorMsg))
    }
  }

  async function handleReset(e) {
    e.preventDefault()
    setError('')
    try {
      const res = await resetPassword(token, password)
      const successMsg = res.data.message || res.data
      setMessage(typeof successMsg === 'string' ? successMsg + ' — te poți autentifica acum.' : 'Parolă resetată cu succes!')
      setStep(3)
    } catch (err) {
      // FIX: Convertim eroarea la string
      const errorMsg = err.response?.data?.error || err.response?.data || 'Token invalid'
      setError(typeof errorMsg === 'string' ? errorMsg : JSON.stringify(errorMsg))
      console.error('Reset error:', err.response?.data) // pentru debug
    }
  }

  return (
    <div className="page-center">
      <div className="card">
        <h2 style={{ marginBottom: 4 }}>Resetare parolă</h2>


        {error   && <div className="error">{error}</div>}
        {message && <div className="success">{message}</div>}

        {step === 1 && (
          <form onSubmit={handleForgot}>
            <div className="field">
              <label>Email cont</label>
              <input type="email" value={email} onChange={e => setEmail(e.target.value)} required />
            </div>
            <button className="btn" type="submit">Trimite token</button>
          </form>
        )}

        {step === 2 && (
          <form onSubmit={handleReset}>
            {resetToken && (
              <div style={{ background: '#fef3c7', borderRadius: 6, padding: 10, marginBottom: 12 }}>
                <p style={{ fontSize: 11, color: '#92400e' }}>Token generat:</p>
                <code style={{ fontSize: 13, fontWeight: 'bold' }}>{resetToken}</code>
              </div>
            )}
            <div className="field">
              <label>Token primit</label>
              <input value={token} onChange={e => setToken(e.target.value)}
                     placeholder="Introdu token-ul" required />
            </div>
            <div className="field">
              <label>Parolă nouă</label>
              <input type="password" value={password}
                     onChange={e => setPassword(e.target.value)} required />
            </div>
            <button className="btn" type="submit">Resetează parola</button>
          </form>
        )}

        {step === 3 && (
          <Link to="/login" className="btn" style={{ display: 'block', textAlign: 'center', textDecoration: 'none', marginTop: 8 }}>
            Mergi la Login
          </Link>
        )}
        
      </div>
    </div>
  )
}