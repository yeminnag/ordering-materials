import { Link } from 'react-router-dom'
import { useAuth } from '../context/AuthContext'

export default function Layout({ store, children }) {
  const { signOut, user } = useAuth()

  return (
    <div className="app-shell">
      <header className="app-header">
        <div className="app-header__brand">
          <span className="app-header__logo">SM</span>
          <div>
            <p className="app-header__title">Stock management system</p>
            {store && <p className="app-header__store">{store.name}</p>}
          </div>
        </div>
        <nav className="app-header__nav">
          {store && (
            <Link to="/products" className="nav-link">Products</Link>
          )}
          <span className="app-header__eyebrow">by team vibe</span>
          <span className="user-badge">
            {store?.role === 'owner' ? 'Admin' : 'Staff'}
          </span>
          <span className="user-email">{user?.email}</span>
          <button type="button" className="btn btn--ghost" onClick={signOut}>
            Log out
          </button>
        </nav>
      </header>
      <main className="app-main">{children}</main>
    </div>
  )
}
