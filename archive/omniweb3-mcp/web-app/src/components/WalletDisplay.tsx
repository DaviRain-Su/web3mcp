interface WalletDisplayProps {
  address: string
}

export default function WalletDisplay({ address }: WalletDisplayProps) {
  return (
    <div className="text-left mb-6">
      <p className="text-gray-400 text-sm mb-2">Wallet Address:</p>
      <p className="text-white font-mono text-sm bg-black/30 p-3 rounded-lg break-all">
        {address}
      </p>
    </div>
  )
}
