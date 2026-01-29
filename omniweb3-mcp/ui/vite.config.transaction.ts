import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { viteSingleFile } from 'vite-plugin-singlefile';

// Single-file build for Transaction Viewer
export default defineConfig({
  plugins: [react(), viteSingleFile()],
  build: {
    outDir: 'dist-single/transaction',
    emptyOutDir: true,
    rollupOptions: {
      input: './src/transaction/index.html',
    },
  },
});
