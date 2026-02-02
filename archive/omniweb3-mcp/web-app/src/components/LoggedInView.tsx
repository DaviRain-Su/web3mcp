import { usePrivy } from '@privy-io/react-auth'
import { useEffect, useState } from 'react'
import WalletDisplay from './WalletDisplay'
import TokenDisplay from './TokenDisplay'
import MCPConfigDisplay from './MCPConfigDisplay'

export default function LoggedInView() {
  const { user, logout, getAccessToken } = usePrivy()
  const [accessToken, setAccessToken] = useState<string>('')

  useEffect(() => {
    const fetchToken = async () => {
      try {
        const token = await getAccessToken()
        if (token) {
          setAccessToken(token)
        }
      } catch (error) {
        console.error('Failed to get access token:', error)
      }
    }
    fetchToken()
  }, [getAccessToken])

  // Get user display address
  const getDisplayAddress = (): string => {
    if (user?.wallet?.address) {
      return user.wallet.address
    }
    if (user?.linkedAccounts) {
      // Find any wallet account
      const wallet = user.linkedAccounts.find(
        (account) => account.type === 'wallet' || account.type === 'smart_wallet'
      )
      if (wallet && 'address' in wallet) {
        return (wallet as { address: string }).address
      }
    }
    if (user?.email?.address) {
      return user.email.address
    }
    if (user?.google?.email) {
      return user.google.email
    }
    return user?.id || 'Unknown'
  }

  return (
    <div>
      {/* Success icon */}
      <div className="mb-6">
        <div className="w-16 h-16 bg-green-500/20 rounded-full flex items-center justify-center mx-auto mb-4">
          <svg className="w-8 h-8 text-green-400" fill="none" stroke="currentColor" viewBox="0 0 24 24">
            <path strokeLinecap="round" strokeLinejoin="round" strokeWidth={2} d="M5 13l4 4L19 7" />
          </svg>
        </div>
        <p className="text-green-400 font-semibold">Connected!</p>
      </div>

      {/* Wallet address */}
      <WalletDisplay address={getDisplayAddress()} />

      {/* Access token */}
      <TokenDisplay token={accessToken} />

      {/* MCP config example */}
      <MCPConfigDisplay token={accessToken} />

      {/* Logout button */}
      <button
        onClick={logout}
        className="w-full bg-red-500/20 hover:bg-red-500/30
                   text-red-400 font-semibold py-3 px-6 rounded-xl
                   transition-all duration-200"
      >
        Disconnect
      </button>
    </div>
  )
}
