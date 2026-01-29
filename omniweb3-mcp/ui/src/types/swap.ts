export interface Token {
  symbol: string;
  name: string;
  address: string;
  decimals: number;
  logoUri?: string;
  balance?: string;
}

export interface SwapQuote {
  inputToken: Token;
  outputToken: Token;
  inputAmount: string;
  outputAmount: string;
  priceImpact: string;
  minimumReceived: string;
  route: {
    pool: string;
    fee: string;
  }[];
  gasEstimate: string;
}

export interface SwapResult {
  txHash: string;
  status: 'pending' | 'success' | 'failed';
  inputAmount: string;
  outputAmount: string;
  inputToken: Token;
  outputToken: Token;
}
