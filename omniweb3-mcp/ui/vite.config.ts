import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
// import { viteSingleFile } from 'vite-plugin-singlefile';

export default defineConfig({
  plugins: [
    react(),
    // viteSingleFile(), // TODO: Enable per-page single file bundling
  ],
  build: {
    rollupOptions: {
      input: {
        transaction: './src/transaction/index.html',
        swap: './src/swap/index.html',
        balance: './src/balance/index.html',
      },
    },
    minify: 'esbuild', // Use esbuild for faster minification
  },
});
