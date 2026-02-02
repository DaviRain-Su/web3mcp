import { usePrivy } from '@privy-io/react-auth'

export default function LoginButton() {
  const { login } = usePrivy()

  return (
    <div>
      <p className="text-gray-300 mb-6">Connect your wallet to get started</p>

      {/* Main login button - opens Privy Modal */}
      <button
        onClick={login}
        className="w-full bg-gradient-to-r from-purple-600 to-blue-500
                   hover:from-purple-700 hover:to-blue-600
                   text-white font-semibold py-3 px-6 rounded-xl
                   transition-all duration-200 transform hover:scale-105
                   flex items-center justify-center gap-2"
      >
        <span>Connect Wallet</span>
      </button>

      {/* Supported login methods hint */}
      <div className="mt-6 grid grid-cols-2 gap-2 text-xs text-gray-500">
        <div className="flex items-center justify-center gap-1">
          <span>Email</span>
        </div>
        <div className="flex items-center justify-center gap-1">
          <span>Google / Apple</span>
        </div>
        <div className="flex items-center justify-center gap-1">
          <span>MetaMask</span>
        </div>
        <div className="flex items-center justify-center gap-1">
          <span>Phantom</span>
        </div>
      </div>
    </div>
  )
}
