import { useState, useEffect } from 'react';
import {
  Container,
  Card,
  Group,
  Text,
  Badge,
  ThemeIcon,
  Stack,
  CopyButton,
  ActionIcon,
  Tooltip,
  Table,
  Progress,
  Divider,
  Button,
  Loader,
  Center,
} from '@mantine/core';
import {
  IconCheck,
  IconX,
  IconClock,
  IconCopy,
  IconExternalLink,
  IconArrowRight,
  IconRefresh,
} from '@tabler/icons-react';
import { useMCP } from '../../hooks/useMCP';
import type { TransactionData } from '../../types/transaction';

interface TransactionViewerProps {
  chain: string;
  txHash: string;
  network?: string;
}

export function TransactionViewer({
  chain,
  txHash,
  network = 'mainnet',
}: TransactionViewerProps) {
  const mcp = useMCP();
  const [data, setData] = useState<TransactionData | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);

  const fetchTransaction = async () => {
    try {
      setLoading(true);
      setError(null);

      if (!mcp) {
        setError('MCP client not initialized');
        setLoading(false);
        return;
      }

      const result = await mcp.callTool('get_transaction', {
        chain,
        tx_hash: txHash,
        network,
        _ui: true,
      });

      // Handle undefined result
      if (!result) {
        setError('No response from MCP Host. Make sure the UI is running inside an MCP Host iframe.');
        return;
      }

      // Handle error result
      if (result.isError) {
        const errorMsg = result.content?.[0]?.text || 'Failed to fetch transaction';
        setError(errorMsg);
        return;
      }

      const textItem = result.content?.find(
        (item) => item.type === 'text' && 'text' in item && item.text
      );
      if (textItem && textItem.type === 'text' && textItem.text) {
        try {
          const parsed = JSON.parse(textItem.text) as TransactionData;
          setData(parsed);
        } catch (parseErr) {
          setError('Failed to parse transaction data');
        }
      } else {
        setError('Empty response from server');
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Unknown error');
    } finally {
      setLoading(false);
    }
  };

  useEffect(() => {
    if (!mcp) return; // Wait for MCP client to initialize

    fetchTransaction();

    // Auto-refresh if transaction is pending
    const intervalId =
      data?.transaction.status === 'pending'
        ? setInterval(fetchTransaction, 10000)
        : undefined;

    return () => {
      if (intervalId) clearInterval(intervalId);
    };
  }, [chain, txHash, network, mcp]);

  if (loading && !data) {
    return (
      <Center style={{ minHeight: '400px' }}>
        <Stack align="center" gap="md">
          <Loader size="lg" />
          <Text c="dimmed">Loading transaction...</Text>
        </Stack>
      </Center>
    );
  }

  if (error) {
    return (
      <Center style={{ minHeight: '400px' }}>
        <Stack align="center" gap="md">
          <ThemeIcon size="xl" color="red" radius="xl">
            <IconX size={24} />
          </ThemeIcon>
          <Text c="red">{error}</Text>
          <Button onClick={fetchTransaction} leftSection={<IconRefresh size={16} />}>
            Retry
          </Button>
        </Stack>
      </Center>
    );
  }

  if (!data) {
    return (
      <Center style={{ minHeight: '400px' }}>
        <Text c="dimmed">No transaction data</Text>
      </Center>
    );
  }

  const { transaction, receipt } = data;
  const isSuccess = transaction.status === '0x1' || transaction.status === 'success';
  const isPending = !transaction.status || transaction.status === 'pending';
  const isFailed = transaction.status === '0x0' || transaction.status === 'failed';

  const statusColor = isSuccess ? 'green' : isPending ? 'yellow' : 'red';
  const statusIcon = isSuccess ? (
    <IconCheck />
  ) : isPending ? (
    <IconClock />
  ) : (
    <IconX />
  );
  const statusText = isSuccess ? 'Success' : isPending ? 'Pending' : 'Failed';

  const shortHash = `${txHash.slice(0, 6)}...${txHash.slice(-4)}`;
  const shortFrom = `${transaction.from.slice(0, 6)}...${transaction.from.slice(-4)}`;
  const shortTo = transaction.to
    ? `${transaction.to.slice(0, 6)}...${transaction.to.slice(-4)}`
    : 'Contract Creation';

  // Calculate gas metrics
  const gasUsed = BigInt(receipt?.gasUsed || transaction.gasUsed || '0');
  const gasLimit = BigInt(transaction.gasLimit || '0');
  const gasPrice = BigInt(
    receipt?.effectiveGasPrice || transaction.gasPrice || '0'
  );
  const gasUsedPercent = gasLimit > 0n ? Number((gasUsed * 100n) / gasLimit) : 0;
  const totalFee = (gasUsed * gasPrice) / BigInt(1e18);
  const totalFeeStr = (Number(totalFee) / 1000).toFixed(6);

  return (
    <Container size="md" p="md">
      <Stack gap="md">
        {/* Header */}
        <Card shadow="sm" padding="lg" radius="md" withBorder>
          <Group justify="space-between">
            <Group>
              <ThemeIcon size="xl" color={statusColor} radius="xl">
                {statusIcon}
              </ThemeIcon>
              <div>
                <Text size="sm" c="dimmed">
                  Transaction
                </Text>
                <Group gap="xs">
                  <Text size="xl" fw={700}>
                    {shortHash}
                  </Text>
                  <CopyButton value={txHash}>
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
            <Badge color={statusColor} size="lg" radius="sm">
              {statusText}
            </Badge>
          </Group>
        </Card>

        {/* Transaction Flow */}
        <Card shadow="sm" padding="lg" radius="md" withBorder>
          <Text size="lg" fw={600} mb="md">
            Transaction Flow
          </Text>
          <Group justify="center" gap="xl">
            {/* From */}
            <Stack gap="xs" align="center" style={{ flex: 1 }}>
              <ThemeIcon size={48} radius="xl" color="violet">
                <Text size="lg">🟣</Text>
              </ThemeIcon>
              <Text size="xs" c="dimmed">
                From
              </Text>
              <Tooltip label={transaction.from}>
                <Text size="sm" fw={500}>
                  {shortFrom}
                </Text>
              </Tooltip>
              <Text size="xs" c="dimmed">
                EOA
              </Text>
            </Stack>

            {/* Arrow */}
            <IconArrowRight size={32} color="gray" />

            {/* Value */}
            <Stack gap="xs" align="center" style={{ flex: 1 }}>
              <Text size="xl" fw={700} c="blue">
                {(Number(BigInt(transaction.value)) / 1e18).toFixed(4)}
              </Text>
              <Text size="sm" c="dimmed">
                {chain.toUpperCase()}
              </Text>
            </Stack>

            {/* Arrow */}
            <IconArrowRight size={32} color="gray" />

            {/* To */}
            <Stack gap="xs" align="center" style={{ flex: 1 }}>
              <ThemeIcon size={48} radius="xl" color="blue">
                <Text size="lg">🔵</Text>
              </ThemeIcon>
              <Text size="xs" c="dimmed">
                To
              </Text>
              <Tooltip label={transaction.to || 'Contract Creation'}>
                <Text size="sm" fw={500}>
                  {shortTo}
                </Text>
              </Tooltip>
              <Text size="xs" c="dimmed">
                {transaction.to ? 'Contract' : 'Creation'}
              </Text>
            </Stack>
          </Group>
        </Card>

        {/* Details */}
        <Card shadow="sm" padding="lg" radius="md" withBorder>
          <Text size="lg" fw={600} mb="md">
            Details
          </Text>
          <Table striped highlightOnHover>
            <tbody>
              {transaction.blockNumber && (
                <tr>
                  <td>
                    <Text c="dimmed">Block</Text>
                  </td>
                  <td>
                    <Text>#{parseInt(transaction.blockNumber, 16)}</Text>
                  </td>
                </tr>
              )}
              {transaction.timestamp && (
                <tr>
                  <td>
                    <Text c="dimmed">Timestamp</Text>
                  </td>
                  <td>
                    <Text>
                      {new Date(
                        parseInt(transaction.timestamp, 16) * 1000
                      ).toLocaleString()}
                    </Text>
                  </td>
                </tr>
              )}
              <tr>
                <td>
                  <Text c="dimmed">Network</Text>
                </td>
                <td>
                  <Badge>{`${chain} ${network}`}</Badge>
                </td>
              </tr>
              {transaction.nonce && (
                <tr>
                  <td>
                    <Text c="dimmed">Nonce</Text>
                  </td>
                  <td>
                    <Text>{parseInt(transaction.nonce, 16)}</Text>
                  </td>
                </tr>
              )}
            </tbody>
          </Table>
        </Card>

        {/* Gas Analysis */}
        <Card shadow="sm" padding="lg" radius="md" withBorder>
          <Text size="lg" fw={600} mb="md">
            Gas Analysis
          </Text>
          <Stack gap="sm">
            <Group justify="space-between">
              <Text c="dimmed">Gas Limit</Text>
              <Text>{gasLimit.toLocaleString()}</Text>
            </Group>
            <Progress
              value={gasUsedPercent}
              color={gasUsedPercent > 90 ? 'red' : 'blue'}
              size="lg"
              radius="xl"
            />
            <Group justify="space-between">
              <Text size="xs" c="dimmed">
                {gasUsed.toLocaleString()} used ({gasUsedPercent.toFixed(1)}%)
              </Text>
            </Group>
            <Group justify="space-between">
              <Text c="dimmed">Gas Price</Text>
              <Text>{(Number(gasPrice) / 1e9).toFixed(2)} Gwei</Text>
            </Group>
            <Divider />
            <Group justify="space-between">
              <Text fw={600}>Total Fee</Text>
              <Text fw={600} c="blue">
                {totalFeeStr} {chain.toUpperCase()}
              </Text>
            </Group>
          </Stack>
        </Card>

        {/* Action Buttons */}
        <Group justify="center" gap="md">
          <Button
            leftSection={<IconRefresh size={16} />}
            onClick={fetchTransaction}
            loading={loading}
            variant="light"
          >
            Refresh
          </Button>
          <Button
            leftSection={<IconExternalLink size={16} />}
            component="a"
            href={`https://testnet.bscscan.com/tx/${txHash}`}
            target="_blank"
            variant="light"
          >
            View on Explorer
          </Button>
        </Group>
      </Stack>
    </Container>
  );
}
