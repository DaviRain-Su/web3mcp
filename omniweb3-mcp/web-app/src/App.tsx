import { usePrivy } from '@privy-io/react-auth'
import LoginButton from './components/LoginButton'
import LoggedInView from './components/LoggedInView'
import LoadingSpinner from './components/LoadingSpinner'

function App() {
  const { ready, authenticated } = usePrivy()

  return (
    <div className="min-h-screen bg-gradient-main flex items-center justify-center p-4">
      <div className="glass rounded-2xl p-8 max-w-md w-full text-center">
        {/* Header */}
        <div className="mb-8">
          <h1 className="text-4xl font-bold gradient-text mb-2">OmniWeb3 MCP</h1>
          <p className="text-gray-400">Cross-chain Web3 MCP for AI Agents</p>
        </div>

        {/* Content */}
        {!ready ? (
          <LoadingSpinner message="Initializing..." />
        ) : authenticated ? (
          <LoggedInView />
        ) : (
          <LoginButton />
        )}

        {/* Footer */}
        <div className="mt-8 pt-6 border-t border-white/10">
          <p className="text-gray-500 text-sm">
            MCP Endpoint: <code className="text-purple-400">https://api.web3mcp.app</code>
          </p>
        </div>
      </div>
    </div>
  )
}

export default App
