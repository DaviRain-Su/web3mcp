import { useState, useEffect } from 'react';
import {
  Container,
  Card,
  Stack,
  Group,
  Text,
  Badge,
  ThemeIcon,
  Table,
  Progress,
  Button,
  Loader,
  Center,
  CopyButton,
  ActionIcon,
  Tooltip,
  RingProgress,
  SimpleGrid,
  Alert,
} from '@mantine/core';
import {
  IconRefresh,
  IconCopy,
  IconTrendingUp,
  IconTrendingDown,
  IconWallet,
  IconCoins,
  IconAlertTriangle,
} from '@tabler/icons-react';
import { useMCP } from '../../hooks/useMCP';
import type { WalletBalance, TokenBalance } from '../../types/balance';

interface BalanceDashboardProps {
  chain: string;
  address: string;
  network?: string;
}

const CHAIN_SYMBOLS: Record<string, string> = {
  bsc: 'BNB',
  bnb: 'BNB',
  ethereum: 'ETH',
  polygon: 'MATIC',
  avalanche: 'AVAX',
  solana: 'SOL',
  evm: 'ETH',
};

const getChainSymbol = (chainName: string) =>
  CHAIN_SYMBOLS[chainName.toLowerCase()] || chainName.toUpperCase();

const toNumber = (value: string | number | undefined) => {
  const parsed = typeof value === 'number' ? value : parseFloat(value ?? '0');
  return Number.isFinite(parsed) ? parsed : 0;
};

const normalizeToken = (token: any): TokenBalance => {
  const tokenInfo = token?.token ?? {};
  return {
    token: {
      symbol: tokenInfo.symbol ?? 'TOKEN',
      name: tokenInfo.name ?? 'Unknown Token',
      address: tokenInfo.address ?? '',
      decimals: tokenInfo.decimals ?? 18,
      logoUri: tokenInfo.logoUri,
    },
    balance: token?.balance ?? '0',
    balanceRaw: token?.balanceRaw ?? '0',
    valueUsd: token?.valueUsd ?? '0',
    price: token?.price ?? '0',
    priceChange24h: token?.priceChange24h ?? '0',
  };
};

const normalizeWalletBalance = (
  raw: any,
  fallbackChain: string,
  fallbackAddress: string,
  fallbackNetwork: string
): WalletBalance => {
  const now = Math.floor(Date.now() / 1000);
  const resolvedChain = raw?.chain ?? fallbackChain;
  const resolvedAddress = raw?.address ?? fallbackAddress;
  const resolvedNetwork = raw?.network ?? fallbackNetwork;
  const chainSymbol = getChainSymbol(resolvedChain);
  const nativeBalanceRaw = raw?.nativeBalance ?? {};
  const fallbackNativeBalance = raw?.balance_eth ?? raw?.balance_sol ?? raw?.balance ?? '0';

  return {
    address: resolvedAddress,
    chain: resolvedChain,
    network: resolvedNetwork,
    nativeBalance: {
      symbol: nativeBalanceRaw.symbol ?? chainSymbol,
      balance: nativeBalanceRaw.balance ?? fallbackNativeBalance,
      valueUsd: nativeBalanceRaw.valueUsd ?? '0',
    },
    tokens: Array.isArray(raw?.tokens) ? raw.tokens.map(normalizeToken) : [],
    totalValueUsd:
      typeof raw?.totalValueUsd === 'string' ? raw.totalValueUsd : nativeBalanceRaw.valueUsd ?? '0',
    lastUpdated: typeof raw?.lastUpdated === 'number' ? raw.lastUpdated : now,
  };
};

export function BalanceDashboard({
  chain,
  address,
  network = 'mainnet',
}: BalanceDashboardProps) {
  const mcp = useMCP();
  const [data, setData] = useState<WalletBalance | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchBalance = async () => {
    try {
      setLoading(true);
      setError(null);

      if (!mcp) {
        setError('MCP client not initialized');
        setLoading(false);
        return;
      }

      const result = await mcp.callTool('get_balance', {
        chain,
        address,
        network,
        _ui: true,
      });

      if (!result) {
        setError('No response from MCP Host');
        return;
      }

      if (result.isError) {
        setError(result.content?.[0]?.text || 'Failed to fetch balance');
        return;
      }

      const textItem = result.content?.find(
        (item) => item.type === 'text' && 'text' in item && item.text
      );
      if (textItem && textItem.type === 'text' && textItem.text) {
        const parsed = JSON.parse(textItem.text);
        setData(normalizeWalletBalance(parsed, chain, address, network));
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unknown error');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (!mcp) return;
    fetchBalance();
  }, [chain, address, network, mcp]);

  if (loading && !data) {
    return (
      <Center style={{ minHeight: '400px' }}>
        <Stack align="center" gap="md">
          <Loader size="lg" />
          <Text c="dimmed">Loading balances...</Text>
        </Stack>
      </Center>
    );
  }

  if (error) {
    return (
      <Center style={{ minHeight: '400px' }}>
        <Stack align="center" gap="md">
          <ThemeIcon size="xl" color="red" radius="xl">
            <IconAlertTriangle size={24} />
          </ThemeIcon>
          <Text c="red">{error}</Text>
          <Button onClick={fetchBalance} leftSection={<IconRefresh size={16} />}>
            Retry
          </Button>
        </Stack>
      </Center>
    );
  }

  if (!data) {
    return (
      <Center style={{ minHeight: '400px' }}>
        <Text c="dimmed">No balance data</Text>
      </Center>
    );
  }

  const shortAddress = `${address.slice(0, 6)}...${address.slice(-4)}`;
  const totalValue = toNumber(data.totalValueUsd);
  const nativeValue = toNumber(data.nativeBalance.valueUsd);
  const tokensValue = totalValue - nativeValue;

  // Calculate percentages for ring progress
  const nativePercent = totalValue > 0 ? (nativeValue / totalValue) * 100 : 0;
  const sections = [
    {
      value: nativePercent,
      color: 'pink',
      tooltip: `${data.nativeBalance.symbol}: $${nativeValue.toFixed(2)}`,
    },
  ];

  // Add token sections
  data.tokens.forEach((token, index) => {
    const tokenValue = toNumber(token.valueUsd);
    const tokenPercent = totalValue > 0 ? (tokenValue / totalValue) * 100 : 0;
    const colors = ['blue', 'teal', 'green', 'yellow', 'orange'];
    sections.push({
      value: tokenPercent,
      color: colors[index % colors.length],
      tooltip: `${token.token.symbol}: $${tokenValue.toFixed(2)}`,
    });
  });

  return (
    <Container size="lg" p="md">
      <Stack gap="md">
        {/* Header */}
        <Card shadow="sm" padding="lg" radius="md" withBorder>
          <Group justify="space-between">
            <Group>
              <ThemeIcon size="xl" color="violet" radius="xl">
                <IconWallet size={24} />
              </ThemeIcon>
              <div>
                <Text size="sm" c="dimmed">
                  Wallet Address
                </Text>
                <Group gap="xs">
                  <Text size="lg" fw={700}>
                    {shortAddress}
                  </Text>
                  <CopyButton value={address}>
                    {({ copied, copy }) => (
                      <Tooltip label={copied ? 'Copied!' : 'Copy'}>
                        <ActionIcon
                          color={copied ? 'teal' : 'gray'}
                          onClick={copy}
                          variant="subtle"
                        >
                          <IconCopy size={16} />
                        </ActionIcon>
                      </Tooltip>
                    )}
                  </CopyButton>
                </Group>
              </div>
            </Group>
            <Badge color="blue" size="lg" radius="sm">
              {chain} {network}
            </Badge>
          </Group>
        </Card>

        {/* Total Value */}
        <Card shadow="sm" padding="lg" radius="md" withBorder>
          <Group justify="space-between" align="flex-start">
            <Stack gap="xs">
              <Text size="sm" c="dimmed">
                Total Portfolio Value
              </Text>
              <Text size="2.5rem" fw={700} c="blue">
                ${totalValue.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
              </Text>
              <Group gap="xs">
                <Badge variant="light" color="pink">
                  {data.nativeBalance.symbol}: ${nativeValue.toFixed(2)}
                </Badge>
                <Badge variant="light" color="blue">
                  Tokens: ${tokensValue.toFixed(2)}
                </Badge>
              </Group>
            </Stack>
            <RingProgress
              size={140}
              thickness={16}
              sections={sections}
              label={
                <Center>
                  <ThemeIcon size="lg" radius="xl" variant="light">
                    <IconCoins size={20} />
                  </ThemeIcon>
                </Center>
              }
            />
          </Group>
        </Card>

        {/* Native Balance */}
        <Card shadow="sm" padding="lg" radius="md" withBorder>
          <Stack gap="md">
            <Text size="lg" fw={600}>
              Native Balance
            </Text>
            <Group justify="space-between">
              <Group>
                <ThemeIcon size={40} radius="xl" color="pink">
                  <Text size="lg">{data.nativeBalance.symbol[0]}</Text>
                </ThemeIcon>
                <div>
                  <Text fw={600}>{data.nativeBalance.symbol}</Text>
                  <Text size="sm" c="dimmed">
                    {data.nativeBalance.balance}
                  </Text>
                </div>
              </Group>
              <Text size="lg" fw={600}>
                ${nativeValue.toFixed(2)}
              </Text>
            </Group>
          </Stack>
        </Card>

        {/* Token Balances */}
        {data.tokens.length > 0 && (
          <Card shadow="sm" padding="lg" radius="md" withBorder>
            <Stack gap="md">
              <Group justify="space-between">
                <Text size="lg" fw={600}>
                  Token Balances
                </Text>
                <Badge>{data.tokens.length} tokens</Badge>
              </Group>
              <Table striped highlightOnHover>
                <thead>
                  <tr>
                    <th>Token</th>
                    <th>Balance</th>
                    <th>Price</th>
                    <th>24h Change</th>
                    <th>Value</th>
                  </tr>
                </thead>
                <tbody>
                  {data.tokens.map((token, index) => {
                    const priceChange = toNumber(token.priceChange24h);
                    const isPositive = priceChange >= 0;
                    return (
                      <tr key={index}>
                        <td>
                          <Group gap="xs">
                            <ThemeIcon size={32} radius="xl" variant="light">
                              <Text size="sm">{token.token.symbol[0]}</Text>
                            </ThemeIcon>
                            <div>
                              <Text size="sm" fw={500}>
                                {token.token.symbol}
                              </Text>
                              <Text size="xs" c="dimmed">
                                {token.token.name}
                              </Text>
                            </div>
                          </Group>
                        </td>
                        <td>
                          <Text size="sm">{token.balance}</Text>
                        </td>
                        <td>
                            <Text size="sm">${toNumber(token.price).toFixed(4)}</Text>
                        </td>
                        <td>
                          <Badge
                            color={isPositive ? 'green' : 'red'}
                            variant="light"
                            leftSection={
                              isPositive ? (
                                <IconTrendingUp size={14} />
                              ) : (
                                <IconTrendingDown size={14} />
                              )
                            }
                          >
                            {isPositive ? '+' : ''}
                            {priceChange.toFixed(2)}%
                          </Badge>
                        </td>
                        <td>
                          <Text size="sm" fw={500}>
                            ${toNumber(token.valueUsd).toFixed(2)}
                          </Text>
                        </td>
                      </tr>
                    );
                  })}
                </tbody>
              </Table>
            </Stack>
          </Card>
        )}

        {/* Empty State */}
        {data.tokens.length === 0 && (
          <Alert variant="light" color="blue">
            <Text size="sm">No token balances found</Text>
          </Alert>
        )}

        {/* Refresh Button */}
        <Group justify="center">
          <Button
            leftSection={<IconRefresh size={16} />}
            onClick={fetchBalance}
            loading={loading}
            variant="light"
          >
            Refresh
          </Button>
        </Group>

        {/* Last Updated */}
        {data.lastUpdated && (
          <Center>
            <Text size="xs" c="dimmed">
              Last updated: {new Date(data.lastUpdated * 1000).toLocaleString()}
            </Text>
          </Center>
        )}
      </Stack>
    </Container>
  );
}
