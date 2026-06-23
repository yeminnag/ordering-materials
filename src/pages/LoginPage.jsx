import { useState } from 'react'
import { Navigate } from 'react-router-dom'
import { useAuth } from '../context/AuthContext'

export default function LoginPage() {
  const { session, signIn } = useAuth()
  const [email, setEmail] = useState('yeminaung.56jp@gmail.com')
  const [password, setPassword] = useState('')
  const [error, setError] = useState('')
  const [submitting, setSubmitting] = useState(false)

  if (session) return <Navigate to="/products" replace />

  async function handleSubmit(event) {
    event.preventDefault()
    setSubmitting(true)
    setError('')

    try {
      await signIn(email, password)
    } catch (err) {
      setError(err.message)
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="auth-page">
      <div className="auth-card">
        <div className="auth-header">
          <h1>Stock management system</h1>
          <p className="auth-card__eyebrow">by team vibe</p>
        </div>

        <form className="form-stack" onSubmit={handleSubmit}>
          <label className="field">
            <span>Email</span>
            <input
              type="email"
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              required
            />
          </label>

          <label className="field">
            <span>Password</span>
            <input
              type="password"
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="Password set in Supabase"
              required
            />
          </label>

          {error && <p className="form-message form-message--error">{error}</p>}

          <button type="submit" className="btn btn--primary btn--full" disabled={submitting}>
            {submitting ? 'Signing in...' : 'Sign in'}
          </button>
        </form>
      </div>
    </div>
  )
}
