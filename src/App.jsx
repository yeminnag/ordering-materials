import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom'
import { AuthProvider, useAuth } from './context/AuthContext'
import LoginPage from './pages/LoginPage'
import ProductsPage from './pages/ProductsPage'
import './App.css'

function ProtectedRoute({ children }) {
  const { session, loading } = useAuth()

  if (loading) return <div className="loading-screen">読み込み中...</div>
  if (!session) return <Navigate to="/login" replace />
  return children
}

export default function App() {
  return (
    <AuthProvider>
      <BrowserRouter>
        <Routes>
          <Route path="/login" element={<LoginPage />} />
          <Route
            path="/products"
            element={
              <ProtectedRoute>
                <ProductsPage />
              </ProtectedRoute>
            }
          />
          <Route path="*" element={<Navigate to="/products" replace />} />
        </Routes>
      </BrowserRouter>
    </AuthProvider>
  )
}
