import React from 'react';
import ReactDOM from 'react-dom/client';
import { MantineProvider } from '@mantine/core';
import '@mantine/core/styles.css';
import { BalanceDashboard } from '../components/BalanceDashboard';

// Parse URL parameters
const params = new URLSearchParams(window.location.search);
const chain = params.get('chain') || 'bsc';
const address = params.get('address') || '0xc5208d5e7a946d4b9c4dc28747b4f685159e6a71';
const network = params.get('network') || 'testnet';

ReactDOM.createRoot(document.getElementById('app')!).render(
  <React.StrictMode>
    <MantineProvider
      theme={{
        primaryColor: 'violet',
        colors: {
          violet: [
            '#f3f0ff',
            '#e5dbff',
            '#d0bfff',
            '#b197fc',
            '#9775fa',
            '#845ef7',
            '#7950f2',
            '#7048e8',
            '#6741d9',
            '#5f3dc4',
          ],
        },
      }}
    >
      <BalanceDashboard chain={chain} address={address} network={network} />
    </MantineProvider>
  </React.StrictMode>
);
