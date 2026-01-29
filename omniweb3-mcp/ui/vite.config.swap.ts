import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { viteSingleFile } from 'vite-plugin-singlefile';

// Single-file build for Swap Interface
export default defineConfig({
  plugins: [react(), viteSingleFile()],
  build: {
    outDir: 'dist-single/swap',
    emptyOutDir: true,
    rollupOptions: {
      input: './src/swap/index.html',
    },
  },
});
