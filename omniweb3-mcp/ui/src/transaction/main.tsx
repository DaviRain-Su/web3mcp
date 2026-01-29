import React from 'react';
import ReactDOM from 'react-dom/client';
import { MantineProvider } from '@mantine/core';
import { TransactionViewer } from '../components/TransactionViewer';
import '@mantine/core/styles.css';

// Parse URL parameters
const urlParams = new URLSearchParams(window.location.search);
const chain = urlParams.get('chain') || 'bsc';
const txHash = urlParams.get('tx_hash') || '';
const network = urlParams.get('network') || 'testnet';

function App() {
  return (
    <MantineProvider
      theme={{
        primaryColor: 'blue',
        fontFamily: 'Inter, -apple-system, BlinkMacSystemFont, sans-serif',
      }}
    >
      <TransactionViewer chain={chain} txHash={txHash} network={network} />
    </MantineProvider>
  );
}

const root = ReactDOM.createRoot(document.getElementById('app')!);
root.render(<App />);
