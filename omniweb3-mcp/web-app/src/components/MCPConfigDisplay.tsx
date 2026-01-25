import { useState, useMemo } from 'react'

interface MCPConfigDisplayProps {
  token: string
}

export default function MCPConfigDisplay({ token }: MCPConfigDisplayProps) {
  const [copied, setCopied] = useState(false)

  const configJson = useMemo(() => {
    return JSON.stringify({
      mcpServers: {
        omniweb3: {
          command: "npx",
          args: [
            "-y",
            "mcp-remote",
            "https://api.web3mcp.app/",
            "--header",
            `Authorization:Bearer ${token}`
          ]
        }
      }
    }, null, 2)
  }, [token])

  const handleCopy = async () => {
    await navigator.clipboard.writeText(configJson)
    setCopied(true)
    setTimeout(() => setCopied(false), 2000)
  }

  return (
    <div className="text-left mb-6 glass rounded-lg p-4">
      <p className="text-gray-400 text-sm mb-2">Claude Desktop Config:</p>
      <pre className="text-xs text-gray-300 overflow-x-auto whitespace-pre-wrap">
        {configJson}
      </pre>
      <button
        onClick={handleCopy}
        className="mt-2 bg-blue-600 hover:bg-blue-700
                   text-white text-xs py-1 px-2 rounded transition-colors"
      >
        {copied ? 'Copied!' : 'Copy Config'}
      </button>
    </div>
  )
}
