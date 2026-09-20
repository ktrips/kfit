import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'

export default defineConfig({
  plugins: [react()],
  server: {
    port: 5173,
    open: true
  },
  build: {
    outDir: 'dist',
    sourcemap: false,
    minify: 'terser',
    rollupOptions: {
      output: {
        // 変更頻度の低い巨大ライブラリを分離し、アプリ更新時もブラウザキャッシュを再利用させる
        manualChunks(id: string) {
          if (!id.includes('node_modules')) return undefined
          if (id.includes('firebase') || id.includes('@firebase')) return 'vendor-firebase'
          if (id.includes('react') || id.includes('scheduler') || id.includes('zustand')) return 'vendor-react'
          return undefined
        }
      }
    }
  }
})
