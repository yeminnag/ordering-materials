import { useEffect, useState } from 'react'
import { supabase } from '../lib/supabase'
import { useAuth } from '../context/AuthContext'

export function useStore() {
  const { user } = useAuth()
  const [store, setStore] = useState(null)
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState(null)

  useEffect(() => {
    if (!user) {
      setStore(null)
      setLoading(false)
      return
    }

    let cancelled = false

    async function load() {
      setLoading(true)
      setError(null)

      const { data, error: fetchError } = await supabase
        .from('store_members')
        .select('role, stores(id, name, address)')
        .eq('user_id', user.id)
        .maybeSingle()

      if (cancelled) return

      if (fetchError) {
        setError(fetchError.message)
        setStore(null)
      } else if (data?.stores) {
        setStore({ ...data.stores, role: data.role })
      } else {
        setStore(null)
      }

      setLoading(false)
    }

    load()
    return () => { cancelled = true }
  }, [user])

  return { store, loading, error }
}
