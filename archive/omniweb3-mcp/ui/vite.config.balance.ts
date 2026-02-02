import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { viteSingleFile } from 'vite-plugin-singlefile';

// Single-file build for Balance Dashboard
export default defineConfig({
  plugins: [react(), viteSingleFile()],
  build: {
    outDir: 'dist-single/balance',
    emptyOutDir: true,
    rollupOptions: {
      input: './src/balance/index.html',
    },
  },
});
