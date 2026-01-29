import React from 'react';
import ReactDOM from 'react-dom/client';
import { MantineProvider } from '@mantine/core';
import '@mantine/core/styles.css';
import { SwapInterface } from '../components/SwapInterface';

// Parse URL parameters
const params = new URLSearchParams(window.location.search);
const chain = params.get('chain') || 'bsc';
const network = params.get('network') || 'testnet';

ReactDOM.createRoot(document.getElementById('app')!).render(
  <React.StrictMode>
    <MantineProvider
      theme={{
        primaryColor: 'pink',
        colors: {
          pink: [
            '#fff0f6',
            '#ffdeeb',
            '#fcc2d7',
            '#faa2c1',
            '#f783ac',
            '#f06595',
            '#e64980',
            '#d6336c',
            '#c2255c',
            '#a61e4d',
          ],
        },
      }}
    >
      <SwapInterface chain={chain} network={network} />
    </MantineProvider>
  </React.StrictMode>
);
