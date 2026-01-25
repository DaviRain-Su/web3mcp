import React from 'react'
import ReactDOM from 'react-dom/client'
import { PrivyProvider } from '@privy-io/react-auth'
import App from './App'
import './styles/globals.css'

const PRIVY_APP_ID = 'clt574a4m058ovy6y0glgc48j'

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <PrivyProvider
      appId={PRIVY_APP_ID}
      config={{
        appearance: {
          theme: 'dark',
          accentColor: '#7c3aed',
          showWalletLoginFirst: true,
        },
        loginMethods: [
          'email',
          'google',
          'apple',
          'twitter',
          'wallet',
        ],
        embeddedWallets: {
          createOnLogin: 'users-without-wallets',
        },
      }}
    >
      <App />
    </PrivyProvider>
  </React.StrictMode>,
)
