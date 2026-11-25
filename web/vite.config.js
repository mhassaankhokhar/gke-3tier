import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: {
    // Local dev only; in the cluster nginx proxies /api.
    proxy: { '/api': 'http://localhost:3000' },
  },
});
