import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useStore } from '../hooks/useStore'
import Layout from '../components/Layout'

const UNITS = ['pack', 'piece', 'kg', 'bottle', 'bag', 'case']

export default function ProductsPage() {
  const { store, loading: storeLoading, error: storeError } = useStore()
  const [products, setProducts] = useState([])
  const [loading, setLoading] = useState(true)
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState('')
  const [form, setForm] = useState({ name: '', unit: 'pack', target_stock: 10 })

  async function loadProducts() {
    if (!store) return
    setLoading(true)
    setError('')

    const { data, error: fetchError } = await supabase
      .from('products')
      .select('id, name, unit, target_stock')
      .eq('store_id', store.id)
      .eq('is_active', true)
      .order('created_at', { ascending: false })

    if (fetchError) setError(fetchError.message)
    else setProducts(data ?? [])

    setLoading(false)
  }

  useEffect(() => {
    loadProducts()
  }, [store?.id])

  async function handleSubmit(event) {
    event.preventDefault()
    if (!store) return

    setSubmitting(true)
    setError('')

    const { error: insertError } = await supabase.from('products').insert({
      store_id: store.id,
      name: form.name.trim(),
      unit: form.unit,
      target_stock: Number(form.target_stock),
    })

    if (insertError) setError(insertError.message)
    else {
      setForm({ name: '', unit: 'pack', target_stock: 10 })
      await loadProducts()
    }

    setSubmitting(false)
  }

  if (storeLoading) return <div className="loading-screen">Loading...</div>

  if (storeError || !store) {
    return (
      <div className="loading-screen">
        <p>Cannot access this store.</p>
        <p className="muted">
          {storeError ?? 'Ask an admin to add you to store_members.'}
        </p>
      </div>
    )
  }

  return (
    <Layout store={store}>
      <div className="page-grid">
        <section className="page-card">
          <h1>Products</h1>
          <p className="page-lead">
            Register items to track and reorder. Target stock is how much you want on hand each morning.
          </p>

          <form className="form-stack form-stack--inline" onSubmit={handleSubmit}>
            <label className="field">
              <span>Product name</span>
              <input
                type="text"
                value={form.name}
                onChange={(e) => setForm({ ...form, name: e.target.value })}
                placeholder="e.g. Eggs"
                required
              />
            </label>

            <label className="field">
              <span>Unit</span>
              <select value={form.unit} onChange={(e) => setForm({ ...form, unit: e.target.value })}>
                {UNITS.map((unit) => (
                  <option key={unit} value={unit}>{unit}</option>
                ))}
              </select>
            </label>

            <label className="field">
              <span>Target stock</span>
              <input
                type="number"
                min="0"
                value={form.target_stock}
                onChange={(e) => setForm({ ...form, target_stock: e.target.value })}
                required
              />
            </label>

            <button type="submit" className="btn btn--primary" disabled={submitting}>
              {submitting ? 'Adding...' : 'Add product'}
            </button>
          </form>

          {error && <p className="form-message form-message--error">{error}</p>}
        </section>

        <section className="page-card">
          <div className="section-heading">
            <h2>Registered products</h2>
            <span className="badge">{products.length} items</span>
          </div>

          {loading ? (
            <p className="muted">Loading...</p>
          ) : products.length === 0 ? (
            <div className="empty-state">
              <p>No products yet</p>
              <p className="muted">Add your first product (e.g. Eggs) using the form.</p>
            </div>
          ) : (
            <table className="data-table">
              <thead>
                <tr>
                  <th>Product</th>
                  <th>Unit</th>
                  <th>Target stock</th>
                </tr>
              </thead>
              <tbody>
                {products.map((product) => (
                  <tr key={product.id}>
                    <td>{product.name}</td>
                    <td>{product.unit}</td>
                    <td>{product.target_stock} {product.unit}</td>
                  </tr>
                ))}
              </tbody>
            </table>
          )}
        </section>
      </div>
    </Layout>
  )
}
