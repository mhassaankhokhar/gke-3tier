import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

export default defineConfig({
  plugins: [react()],
  server: {
    // Local development only. In the cluster nginx proxies /api, so the app
    // never needs to know an API address — see nginx.conf.
    proxy: { '/api': 'http://localhost:3000' },
  },
});
