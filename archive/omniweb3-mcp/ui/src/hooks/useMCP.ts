import { useEffect, useRef, useState, useCallback } from 'react';
import { getMCPAppClient, MCPAppClient } from '../lib/mcp-app';

/**
 * Hook to get the MCP App client instance (using official SDK)
 */
export function useMCP(): MCPAppClient | null {
  const clientRef = useRef<MCPAppClient | null>(null);
  const [client, setClient] = useState<MCPAppClient | null>(null);

  useEffect(() => {
    if (!clientRef.current) {
      getMCPAppClient('OmniWeb3 Transaction Viewer').then((c) => {
        clientRef.current = c;
        setClient(c);
      });
    }
  }, []);

  return client;
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
    if (!mcp) {
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
        const textItem = result.content?.find(
          (item) => item.type === 'text' && 'text' in item && item.text
        );
        if (textItem && textItem.type === 'text' && textItem.text) {
          try {
            parsedData = JSON.parse(textItem.text) as T;
          } catch {
            parsedData = textItem.text as any;
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
  }, [enabled, mcp, toolName, JSON.stringify(args), refreshInterval]);

  const refetch = useCallback(async () => {
    try {
      setLoading(true);
      if (!mcp) {
        throw new Error('MCP client not initialized');
      }
      const result = await mcp.callTool(toolName, args);

      let parsedData: T | null = null;
      const textItem = result.content?.find(
        (item) => item.type === 'text' && 'text' in item && item.text
      );
      if (textItem && textItem.type === 'text' && textItem.text) {
        try {
          parsedData = JSON.parse(textItem.text) as T;
        } catch {
          parsedData = textItem.text as any;
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
