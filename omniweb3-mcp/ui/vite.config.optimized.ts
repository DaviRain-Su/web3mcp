import { defineConfig } from 'vite';
import react from '@vitejs/plugin-react';

// Optimized production build configuration
export default defineConfig({
  plugins: [react()],
  build: {
    rollupOptions: {
      input: {
        transaction: './src/transaction/index.html',
        swap: './src/swap/index.html',
        balance: './src/balance/index.html',
      },
      output: {
        manualChunks: {
          // Separate vendor chunks
          'react-vendor': ['react', 'react-dom'],
          'mantine-vendor': ['@mantine/core', '@mantine/hooks'],
        },
      },
    },
    minify: 'esbuild',
    target: 'es2020',
    cssCodeSplit: true,
    // Optimize chunk size
    chunkSizeWarningLimit: 600,
    reportCompressedSize: true,
  },
  esbuild: {
    drop: ['console', 'debugger'], // Remove console.log in production
    legalComments: 'none',
  },
});
