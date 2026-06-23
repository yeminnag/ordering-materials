import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useStore } from '../hooks/useStore'
import Layout from '../components/Layout'

const UNITS = ['パック', '個', 'kg', '本', '袋', '箱']

export default function ProductsPage() {
  const { store, loading: storeLoading, error: storeError } = useStore()
  const [products, setProducts] = useState([])
  const [loading, setLoading] = useState(true)
  const [submitting, setSubmitting] = useState(false)
  const [error, setError] = useState('')
  const [form, setForm] = useState({ name: '', unit: 'パック', target_stock: 10 })

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
      setForm({ name: '', unit: 'パック', target_stock: 10 })
      await loadProducts()
    }

    setSubmitting(false)
  }

  if (storeLoading) return <div className="loading-screen">読み込み中...</div>

  if (storeError || !store) {
    return (
      <div className="loading-screen">
        <p>店舗にアクセスできません。</p>
        <p className="muted">{storeError ?? '管理者に store_members への追加を依頼してください。'}</p>
      </div>
    )
  }

  return (
    <Layout store={store}>
      <div className="page-grid">
        <section className="page-card">
          <h1>商品管理</h1>
          <p className="page-lead">
            発注する商品を登録します。目標在庫数は翌朝に用意したい数量です。
          </p>

          <form className="form-stack form-stack--inline" onSubmit={handleSubmit}>
            <label className="field">
              <span>商品名</span>
              <input
                type="text"
                value={form.name}
                onChange={(e) => setForm({ ...form, name: e.target.value })}
                placeholder="例：卵"
                required
              />
            </label>

            <label className="field">
              <span>単位</span>
              <select value={form.unit} onChange={(e) => setForm({ ...form, unit: e.target.value })}>
                {UNITS.map((unit) => (
                  <option key={unit} value={unit}>{unit}</option>
                ))}
              </select>
            </label>

            <label className="field">
              <span>目標在庫数</span>
              <input
                type="number"
                min="0"
                value={form.target_stock}
                onChange={(e) => setForm({ ...form, target_stock: e.target.value })}
                required
              />
            </label>

            <button type="submit" className="btn btn--primary" disabled={submitting}>
              {submitting ? '追加中...' : '商品を追加'}
            </button>
          </form>

          {error && <p className="form-message form-message--error">{error}</p>}
        </section>

        <section className="page-card">
          <div className="section-heading">
            <h2>登録済み商品</h2>
            <span className="badge">{products.length} 件</span>
          </div>

          {loading ? (
            <p className="muted">読み込み中...</p>
          ) : products.length === 0 ? (
            <div className="empty-state">
              <p>まだ商品がありません</p>
              <p className="muted">最初の商品（例：卵）を追加してください。</p>
            </div>
          ) : (
            <table className="data-table">
              <thead>
                <tr>
                  <th>商品名</th>
                  <th>単位</th>
                  <th>目標在庫</th>
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
