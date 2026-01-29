import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';
import { viteSingleFile } from 'vite-plugin-singlefile';

// https://vite.dev/config/
export default defineConfig({
  plugins: [
    react(),
    viteSingleFile(), // Bundle everything into single HTML files (官方MCP Apps要求)
  ],
  build: {
    rollupOptions: {
      input: {
        transaction: './src/transaction/index.html',
        swap: './src/swap/index.html',
        balance: './src/balance/index.html',
      },
    },
    minify: 'esbuild',
    cssCodeSplit: false, // Inline CSS
    assetsInlineLimit: 100000000, // Inline all assets
  },
});
