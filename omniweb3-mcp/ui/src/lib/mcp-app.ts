/**
 * Official MCP Apps SDK Client
 * Using @modelcontextprotocol/ext-apps
 */
import { App } from '@modelcontextprotocol/ext-apps';

export interface ToolCallResult<T = any> {
  content: Array<{
    type: 'text' | 'resource';
    text?: string;
    resource?: {
      uri: string;
      mimeType: string;
      text: string;
    };
  }>;
  isError?: boolean;
  _meta?: Record<string, any>;
  data?: T;
}

/**
 * MCP App Client using official SDK
 */
export class MCPAppClient {
  private app: App;
  private connected: boolean = false;
  private connectPromise: Promise<void> | null = null;
  private connectError: Error | null = null;

  constructor(name: string, version: string = '1.0.0') {
    this.app = new App({
      name,
      version,
    });

    // Handle tool results from host
    this.app.ontoolresult = (result) => {
      console.log('[MCP App] Received tool result:', result);
    };

    // Connect to host
    this.connectPromise = this.connect();
  }

  /**
   * Connect to MCP Host
   */
  private async connect() {
    try {
      await this.app.connect();
      this.connected = true;
      this.connectError = null;
      console.log('[MCP App] Connected to host');
    } catch (error) {
      console.error('[MCP App] Failed to connect:', error);
      this.connected = false;
      this.connectError = error instanceof Error ? error : new Error(String(error));
    }
  }

  /**
   * Call an MCP tool via the host
   */
  async callTool<T = any>(
    name: string,
    args: Record<string, any>
  ): Promise<ToolCallResult<T>> {
    if (!this.connected) {
      await this.connectPromise;
      if (!this.connected) {
        throw this.connectError ?? new Error('Not connected to MCP host');
      }
    }

    try {
      const result = await this.app.callServerTool({
        name,
        arguments: args,
      });

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

      return {
        content: result.content,
        isError: result.isError || false,
        data: parsedData,
      };
    } catch (error) {
      console.error('[MCP App] Tool call failed:', error);
      throw error;
    }
  }

  /**
   * Check if connected to host
   */
  isConnected(): boolean {
    return this.connected;
  }

  /**
   * Get the app instance
   */
  getApp(): App {
    return this.app;
  }
}

// Singleton instance
let appClient: MCPAppClient | null = null;

/**
 * Check if we should use mock mode
 */
function shouldUseMock(): boolean {
  return (
    import.meta.env.VITE_USE_MOCK === 'true' ||
    new URLSearchParams(window.location.search).get('mock') === 'true'
  );
}

/**
 * Get or create MCP App client
 */
export async function getMCPAppClient(
  appName: string = 'OmniWeb3 UI'
): Promise<MCPAppClient | any> {
  if (shouldUseMock()) {
    console.log('[MCP App] Using Mock Mode for development');
    const { getMockMCPClient } = await import('./mcp-mock');
    if (!appClient) {
      appClient = getMockMCPClient() as any;
    }
    return appClient;
  }

  if (!appClient) {
    appClient = new MCPAppClient(appName);
  }
  return appClient;
}

/**
 * Destroy the app client
 */
export function destroyMCPAppClient() {
  appClient = null;
}
