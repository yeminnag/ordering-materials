import { useEffect } from 'react'
import { supabase } from '../supabase.js'

function App() {
  useEffect(() => {
    async function testConnection() {
      const { data, error } = await supabase
        .from('stores') // table name ကိုယ့် table နာမည်နဲ့ပြောင်း
        .select('*')
        .limit(1)

      if (error) {
        console.error('Connection Error:', error)
      } else {
        console.log('Connected Successfully!')
        console.log(data)
      }
    }

    testConnection()
  }, [])

  return <h1>Testing Supabase</h1>
}

export default App