export interface TokenBalance {
  token: {
    symbol: string;
    name: string;
    address: string;
    decimals: number;
    logoUri?: string;
  };
  balance: string;
  balanceRaw: string;
  valueUsd: string;
  price: string;
  priceChange24h: string;
}

export interface WalletBalance {
  address: string;
  chain: string;
  network: string;
  nativeBalance: {
    symbol: string;
    balance: string;
    valueUsd: string;
  };
  tokens: TokenBalance[];
  totalValueUsd: string;
  lastUpdated: number;
}
