export interface Transaction {
  hash: string;
  from: string;
  to: string | null;
  value: string;
  gasLimit?: string;
  gasUsed?: string;
  gasPrice?: string;
  maxFeePerGas?: string;
  maxPriorityFeePerGas?: string;
  nonce?: string;
  blockNumber?: string;
  blockHash?: string;
  transactionIndex?: string;
  status?: string;
  timestamp?: string;
  input?: string;
  type?: string;
  chainId?: string;
  confirmations?: number;
}

export interface TransactionReceipt {
  transactionHash: string;
  transactionIndex: string;
  blockHash: string;
  blockNumber: string;
  from: string;
  to: string | null;
  cumulativeGasUsed: string;
  gasUsed: string;
  contractAddress: string | null;
  logs: any[];
  logsBloom: string;
  status: string;
  effectiveGasPrice?: string;
}

export interface TransactionData {
  transaction: Transaction;
  receipt?: TransactionReceipt;
  chain: string;
  network: string;
}
