/**
 * Mock MCP Client for development testing
 */
import type { ToolCallResult } from './mcp-client';

export class MockMCPClient {
  private mockData: Record<string, any> = {
    get_transaction: {
      transaction: {
        hash: '0x5ad4a5e751e4e160fbc1cfe604e679d6081b6e3fb3d13f7161a6e7773842f2fa',
        from: '0xc5208d5e7a946d4b9c4dc28747b4f685159e6a71',
        to: '0xd99d1c33f9fc3444f8101754abc46c52416550d1',
        value: '10000000000000000', // 0.01 BNB
        gasLimit: '0x214f3',
        gasUsed: '0x214f3',
        gasPrice: '0x5f5e100', // 100 Gwei
        nonce: '0x5',
        blockNumber: '0x532150f',
        blockHash: '0x1c85694f894b1d422e09d764257a10f0283bd9e5f749196d975236ae8ce85be6',
        transactionIndex: '0x0',
        status: '0x1', // Success
        timestamp: '0x697ac137',
        type: '0x0',
        chainId: '0x61', // BSC Testnet
      },
      receipt: {
        transactionHash: '0x5ad4a5e751e4e160fbc1cfe604e679d6081b6e3fb3d13f7161a6e7773842f2fa',
        transactionIndex: '0x0',
        blockHash: '0x1c85694f894b1d422e09d764257a10f0283bd9e5f749196d975236ae8ce85be6',
        blockNumber: '0x532150f',
        from: '0xc5208d5e7a946d4b9c4dc28747b4f685159e6a71',
        to: '0xd99d1c33f9fc3444f8101754abc46c52416550d1',
        cumulativeGasUsed: '0x214f3',
        gasUsed: '0x214f3',
        contractAddress: null,
        logs: [],
        logsBloom: '0x00000000...',
        status: '0x1',
        effectiveGasPrice: '0x5f5e100',
      },
      chain: 'bsc',
      network: 'testnet',
    },
    get_tokens: {
      tokens: [
        {
          symbol: 'BNB',
          name: 'Binance Coin',
          address: '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE',
          decimals: 18,
          balance: '1.5420',
        },
        {
          symbol: 'USDT',
          name: 'Tether USD',
          address: '0x337610d27c682E347C9cD60BD4b3b107C9d34dDd',
          decimals: 18,
          balance: '1000.00',
        },
        {
          symbol: 'BUSD',
          name: 'Binance USD',
          address: '0xeD24FC36d5Ee211Ea25A80239Fb8C4Cfd80f12Ee',
          decimals: 18,
          balance: '500.00',
        },
        {
          symbol: 'CAKE',
          name: 'PancakeSwap Token',
          address: '0xFa60D973F7642B748046464e165A65B7323b0DEE',
          decimals: 18,
          balance: '50.00',
        },
      ],
    },
    get_swap_quote: {
      inputToken: {
        symbol: 'BNB',
        name: 'Binance Coin',
        address: '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE',
        decimals: 18,
      },
      outputToken: {
        symbol: 'USDT',
        name: 'Tether USD',
        address: '0x337610d27c682E347C9cD60BD4b3b107C9d34dDd',
        decimals: 18,
      },
      inputAmount: '1.0',
      outputAmount: '312.45',
      priceImpact: '0.12',
      minimumReceived: '310.88',
      route: [
        {
          pool: 'BNB/USDT',
          fee: '0.25',
        },
      ],
      gasEstimate: '0.0008 BNB (~$0.25)',
    },
    execute_swap: {
      txHash: '0x7f8c9a4b2e1d3f6a8c5b9e2d7f4a1c8e5b3d9f2a6c4e8b1d7f3a9c6e2b5d8f1a',
      status: 'success',
      inputAmount: '1.0',
      outputAmount: '312.45',
      inputToken: {
        symbol: 'BNB',
        name: 'Binance Coin',
        address: '0xEeeeeEeeeEeEeeEeEeEeeEEEeeeeEeeeeeeeEEeE',
        decimals: 18,
      },
      outputToken: {
        symbol: 'USDT',
        name: 'Tether USD',
        address: '0x337610d27c682E347C9cD60BD4b3b107C9d34dDd',
        decimals: 18,
      },
    },
    get_wallet_balance: {
      address: '0xc5208d5e7a946d4b9c4dc28747b4f685159e6a71',
      chain: 'bsc',
      network: 'testnet',
      nativeBalance: {
        symbol: 'BNB',
        balance: '1.5420',
        valueUsd: '482.56',
      },
      tokens: [
        {
          token: {
            symbol: 'USDT',
            name: 'Tether USD',
            address: '0x337610d27c682E347C9cD60BD4b3b107C9d34dDd',
            decimals: 18,
          },
          balance: '1000.00',
          balanceRaw: '1000000000000000000000',
          valueUsd: '1000.00',
          price: '1.00',
          priceChange24h: '0.01',
        },
        {
          token: {
            symbol: 'BUSD',
            name: 'Binance USD',
            address: '0xeD24FC36d5Ee211Ea25A80239Fb8C4Cfd80f12Ee',
            decimals: 18,
          },
          balance: '500.00',
          balanceRaw: '500000000000000000000',
          valueUsd: '500.00',
          price: '1.00',
          priceChange24h: '-0.02',
        },
        {
          token: {
            symbol: 'CAKE',
            name: 'PancakeSwap Token',
            address: '0xFa60D973F7642B748046464e165A65B7323b0DEE',
            decimals: 18,
          },
          balance: '50.00',
          balanceRaw: '50000000000000000000',
          valueUsd: '115.50',
          price: '2.31',
          priceChange24h: '5.42',
        },
        {
          token: {
            symbol: 'ETH',
            name: 'Ethereum',
            address: '0x8BaBbB98678facC7342735486C851ABD7A0d17Ca',
            decimals: 18,
          },
          balance: '0.1234',
          balanceRaw: '123400000000000000',
          valueUsd: '289.76',
          price: '2348.00',
          priceChange24h: '-2.15',
        },
      ],
      totalValueUsd: '2387.82',
      lastUpdated: Math.floor(Date.now() / 1000),
    },
  };

  async callTool<T = any>(
    name: string,
    args: Record<string, any>
  ): Promise<ToolCallResult<T>> {
    console.log('[MockMCP] Tool call:', name, args);

    // Simulate network delay
    await new Promise((resolve) => setTimeout(resolve, 500));

    // Return mock data
    const mockResult = this.mockData[name];
    if (mockResult) {
      return {
        content: [
          {
            type: 'text',
            text: JSON.stringify(mockResult),
          },
        ],
        isError: false,
      };
    }

    // Return error for unknown tools
    return {
      content: [
        {
          type: 'text',
          text: `Mock data not available for tool: ${name}`,
        },
      ],
      isError: true,
    };
  }

  destroy() {
    // No cleanup needed for mock
  }
}

let mockClient: MockMCPClient | null = null;

export function getMockMCPClient(): MockMCPClient {
  if (!mockClient) {
    mockClient = new MockMCPClient();
  }
  return mockClient;
}
