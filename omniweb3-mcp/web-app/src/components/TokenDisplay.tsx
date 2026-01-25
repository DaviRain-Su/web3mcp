import { useState } from 'react'

interface TokenDisplayProps {
  token: string
}

export default function TokenDisplay({ token }: TokenDisplayProps) {
  const [copied, setCopied] = useState(false)

  const handleCopy = async () => {
    await navigator.clipboard.writeText(token)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  return (
    <div className="text-left mb-6">
      <p className="text-gray-400 text-sm mb-2">Your Access Token:</p>
      <div className="relative">
        <textarea
          readOnly
          value={token}
          className="w-full text-white font-mono text-xs bg-black/30
                     p-3 rounded-lg h-24 resize-none border-none
                     focus:outline-none focus:ring-2 focus:ring-purple-500/50"
        />
        <button
          onClick={handleCopy}
          className="absolute top-2 right-2 bg-purple-600 hover:bg-purple-700
                     text-white text-xs py-1 px-2 rounded transition-colors"
        >
          {copied ? 'Copied!' : 'Copy'}
        </button>
      </div>
    </div>
  )
}
