import { useEffect, useRef, useState, useCallback } from 'react';
import { getMCPClient, MCPClient } from '../lib/mcp-client';

/**
 * Hook to get the MCP client instance
 */
export function useMCP(): MCPClient {
  const clientRef = useRef<MCPClient | null>(null);

  if (!clientRef.current) {
    clientRef.current = getMCPClient();
  }

  return clientRef.current;
}

/**
 * Hook to call an MCP tool with loading state
 */
export function useMCPTool<T = any>(
  toolName: string,
  args: Record<string, any>,
  options?: {
    enabled?: boolean;
    refreshInterval?: number;
  }
) {
  const mcp = useMCP();
  const [data, setData] = useState<T | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<Error | null>(null);

  const enabled = options?.enabled ?? true;
  const refreshInterval = options?.refreshInterval;

  useEffect(() => {
    if (!enabled) {
      setLoading(false);
      return;
    }

    let cancelled = false;

    const fetchData = async () => {
      try {
        setLoading(true);
        const result = await mcp.callTool(toolName, args);

        if (cancelled) return;

        // Parse result
        let parsedData: T | null = null;
        if (result.content && result.content.length > 0) {
          const content = result.content[0];
          if (content.type === 'text' && content.text) {
            try {
              parsedData = JSON.parse(content.text) as T;
            } catch {
              parsedData = content.text as any;
            }
          }
        }

        setData(parsedData);
        setError(null);
      } catch (err) {
        if (cancelled) return;
        setError(err instanceof Error ? err : new Error(String(err)));
      } finally {
        if (!cancelled) {
          setLoading(false);
        }
      }
    };

    fetchData();

    // Set up refresh interval if specified
    let intervalId: number | undefined;
    if (refreshInterval && refreshInterval > 0) {
      intervalId = window.setInterval(fetchData, refreshInterval);
    }

    return () => {
      cancelled = true;
      if (intervalId) {
        window.clearInterval(intervalId);
      }
    };
  }, [enabled, toolName, JSON.stringify(args), refreshInterval]);

  const refetch = useCallback(async () => {
    try {
      setLoading(true);
      const result = await mcp.callTool(toolName, args);

      let parsedData: T | null = null;
      if (result.content && result.content.length > 0) {
        const content = result.content[0];
        if (content.type === 'text' && content.text) {
          try {
            parsedData = JSON.parse(content.text) as T;
          } catch {
            parsedData = content.text as any;
          }
        }
      }

      setData(parsedData);
      setError(null);
    } catch (err) {
      setError(err instanceof Error ? err : new Error(String(err)));
    } finally {
      setLoading(false);
    }
  }, [mcp, toolName, JSON.stringify(args)]);

  return { data, loading, error, refetch };
}
