/**
 * MCP Client for postMessage communication between UI and Host
 */

export interface MCPRequest {
  jsonrpc: '2.0';
  id: number;
  method: string;
  params: {
    name: string;
    arguments: Record<string, any>;
  };
}

export interface MCPResponse<T = any> {
  jsonrpc: '2.0';
  id: number;
  result?: T;
  error?: {
    code: number;
    message: string;
    data?: any;
  };
}

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
  data?: T; // Parsed data
}

export class MCPClient {
  private requestId = 0;
  private pending = new Map<
    number,
    { resolve: (value: any) => void; reject: (reason: any) => void }
  >();
  private messageHandler: ((event: MessageEvent) => void) | null = null;

  constructor() {
    this.messageHandler = this.handleMessage.bind(this);
    window.addEventListener('message', this.messageHandler);
  }

  /**
   * Call an MCP tool
   */
  async callTool<T = any>(
    name: string,
    args: Record<string, any>
  ): Promise<ToolCallResult<T>> {
    const id = ++this.requestId;
    const request: MCPRequest = {
      jsonrpc: '2.0',
      id,
      method: 'tools/call',
      params: {
        name,
        arguments: args,
      },
    };

    return new Promise((resolve, reject) => {
      this.pending.set(id, { resolve, reject });

      // Send to Host
      window.parent.postMessage(request, '*');

      // Timeout after 30 seconds
      setTimeout(() => {
        if (this.pending.has(id)) {
          this.pending.delete(id);
          reject(new Error('Request timeout'));
        }
      }, 30000);
    });
  }

  /**
   * Handle messages from Host
   */
  private handleMessage(event: MessageEvent) {
    const response: MCPResponse = event.data;

    // Validate response format
    if (
      !response ||
      typeof response !== 'object' ||
      response.jsonrpc !== '2.0' ||
      typeof response.id !== 'number'
    ) {
      return;
    }

    if (this.pending.has(response.id)) {
      const { resolve, reject } = this.pending.get(response.id)!;
      this.pending.delete(response.id);

      if (response.error) {
        reject(new Error(response.error.message));
      } else {
        resolve(response.result);
      }
    }
  }

  /**
   * Cleanup
   */
  destroy() {
    if (this.messageHandler) {
      window.removeEventListener('message', this.messageHandler);
      this.messageHandler = null;
    }
    this.pending.clear();
  }
}

// Singleton instance
let mcpClient: MCPClient | null = null;

// Check if we should use mock mode
function shouldUseMock(): boolean {
  return import.meta.env.VITE_USE_MOCK === 'true' ||
         new URLSearchParams(window.location.search).get('mock') === 'true';
}

export async function getMCPClient(): Promise<MCPClient | any> {
  if (shouldUseMock()) {
    console.log('[MCP] Using Mock Mode for development');
    const { getMockMCPClient } = await import('./mcp-mock');
    if (!mcpClient) {
      mcpClient = getMockMCPClient() as any;
    }
    return mcpClient;
  }

  if (!mcpClient) {
    mcpClient = new MCPClient();
  }
  return mcpClient;
}

export function destroyMCPClient() {
  if (mcpClient) {
    mcpClient.destroy();
    mcpClient = null;
  }
}
