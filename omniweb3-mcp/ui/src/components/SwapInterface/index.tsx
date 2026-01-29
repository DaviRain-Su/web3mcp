import { useState, useEffect } from 'react';
import {
  Container,
  Card,
  Stack,
  Group,
  Text,
  NumberInput,
  Select,
  Button,
  Divider,
  ThemeIcon,
  Badge,
  Loader,
  Center,
  ActionIcon,
  Slider,
  Collapse,
  Alert,
} from '@mantine/core';
import {
  IconArrowDown,
  IconSettings,
  IconRefresh,
  IconArrowsUpDown,
  IconCheck,
  IconAlertTriangle,
} from '@tabler/icons-react';
import { useMCP } from '../../hooks/useMCP';
import type { Token, SwapQuote, SwapResult } from '../../types/swap';

interface SwapInterfaceProps {
  chain: string;
  network?: string;
}

export function SwapInterface({ chain, network = 'mainnet' }: SwapInterfaceProps) {
  const mcp = useMCP();
  const [tokens, setTokens] = useState<Token[]>([]);
  const [inputToken, setInputToken] = useState<Token | null>(null);
  const [outputToken, setOutputToken] = useState<Token | null>(null);
  const [inputAmount, setInputAmount] = useState<string>('');
  const [outputAmount, setOutputAmount] = useState<string>('');
  const [quote, setQuote] = useState<SwapQuote | null>(null);
  const [loading, setLoading] = useState(false);
  const [swapping, setSwapping] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [slippage, setSlippage] = useState(0.5);
  const [result, setResult] = useState<SwapResult | null>(null);

  // Fetch available tokens
  useEffect(() => {
    const fetchTokens = async () => {
      if (!mcp) return;

      try {
        const result = await mcp.callTool('get_tokens', { chain, network });
        const textItem = result.content?.find(
          (item) => item.type === 'text' && 'text' in item && item.text
        );
        if (textItem && textItem.type === 'text' && textItem.text) {
          const parsed = JSON.parse(textItem.text);
          setTokens(parsed.tokens || []);
          if (parsed.tokens?.length > 0) {
            setInputToken(parsed.tokens[0]);
            setOutputToken(parsed.tokens[1]);
          }
        }
      } catch (err) {
        console.error('Failed to fetch tokens:', err);
      }
    };

    fetchTokens();
  }, [mcp, chain, network]);

  // Fetch quote when input changes
  useEffect(() => {
    if (!inputToken || !outputToken || !inputAmount || parseFloat(inputAmount) <= 0) {
      setQuote(null);
      setOutputAmount('');
      return;
    }

    const fetchQuote = async () => {
      setLoading(true);
      setError(null);

      try {
        if (!mcp) {
          setError('MCP client not initialized');
          return;
        }

        const result = await mcp.callTool('get_swap_quote', {
          chain,
          network,
          input_token: inputToken.address,
          output_token: outputToken.address,
          amount: inputAmount,
          slippage: slippage.toString(),
        });

        if (!result) {
          setError('No response from MCP Host');
          return;
        }

        if (result.isError) {
          setError(result.content?.[0]?.text || 'Failed to get quote');
          return;
        }

        const textItem = result.content?.find(
          (item) => item.type === 'text' && 'text' in item && item.text
        );
        if (textItem && textItem.type === 'text' && textItem.text) {
          const parsed = JSON.parse(textItem.text) as SwapQuote;
          setQuote(parsed);
          setOutputAmount(parsed.outputAmount);
        }
      } catch (err) {
        setError(err instanceof Error ? err.message : 'Failed to get quote');
      } finally {
        setLoading(false);
      }
    };

    const timeoutId = setTimeout(fetchQuote, 500);
    return () => clearTimeout(timeoutId);
  }, [inputToken, outputToken, inputAmount, slippage, mcp, chain, network]);

  const handleSwap = async () => {
    if (!quote || !inputToken || !outputToken) return;

    setSwapping(true);
    setError(null);

    try {
      if (!mcp) {
        setError('MCP client not initialized');
        return;
      }

      const result = await mcp.callTool('execute_swap', {
        chain,
        network,
        input_token: inputToken.address,
        output_token: outputToken.address,
        amount: inputAmount,
        slippage: slippage.toString(),
      });

      if (!result) {
        setError('No response from MCP Host');
        return;
      }

      if (result.isError) {
        setError(result.content?.[0]?.text || 'Swap failed');
        return;
      }

      const textItem = result.content?.find(
        (item) => item.type === 'text' && 'text' in item && item.text
      );
      if (textItem && textItem.type === 'text' && textItem.text) {
        const parsed = JSON.parse(textItem.text) as SwapResult;
        setResult(parsed);
        setInputAmount('');
        setOutputAmount('');
        setQuote(null);
      }
    } catch (err) {
      setError(err instanceof Error ? err.message : 'Swap failed');
    } finally {
      setSwapping(false);
    }
  };

  const handleSwitchTokens = () => {
    const temp = inputToken;
    setInputToken(outputToken);
    setOutputToken(temp);
    setInputAmount(outputAmount);
    setOutputAmount('');
  };

  const tokenOptions = tokens.map((token) => ({
    value: token.address,
    label: `${token.symbol} - ${token.name}`,
  }));

  if (!mcp) {
    return (
      <Center style={{ minHeight: '400px' }}>
        <Stack align="center" gap="md">
          <Loader size="lg" />
          <Text c="dimmed">Initializing...</Text>
        </Stack>
      </Center>
    );
  }

  return (
    <Container size="sm" p="md">
      <Stack gap="md">
        {/* Header */}
        <Group justify="space-between">
          <Text size="xl" fw={700}>
            Swap
          </Text>
          <ActionIcon
            variant={settingsOpen ? 'filled' : 'light'}
            onClick={() => setSettingsOpen(!settingsOpen)}
          >
            <IconSettings size={20} />
          </ActionIcon>
        </Group>

        {/* Settings */}
        <Collapse in={settingsOpen}>
          <Card shadow="sm" padding="md" radius="md" withBorder>
            <Stack gap="sm">
              <Text size="sm" fw={500}>
                Slippage Tolerance
              </Text>
              <Group gap="xs">
                {[0.1, 0.5, 1.0].map((value) => (
                  <Button
                    key={value}
                    size="xs"
                    variant={slippage === value ? 'filled' : 'light'}
                    onClick={() => setSlippage(value)}
                  >
                    {value}%
                  </Button>
                ))}
              </Group>
              <Slider
                value={slippage}
                onChange={setSlippage}
                min={0.1}
                max={5}
                step={0.1}
                marks={[
                  { value: 0.1, label: '0.1%' },
                  { value: 5, label: '5%' },
                ]}
              />
              <Text size="xs" c="dimmed">
                Your transaction will revert if the price changes unfavorably by more than{' '}
                {slippage}%
              </Text>
            </Stack>
          </Card>
        </Collapse>

        {/* Swap Card */}
        <Card shadow="sm" padding="lg" radius="md" withBorder>
          <Stack gap="md">
            {/* Input Token */}
            <Stack gap="xs">
              <Group justify="space-between">
                <Text size="xs" c="dimmed">
                  From
                </Text>
                {inputToken?.balance && (
                  <Text size="xs" c="dimmed">
                    Balance: {inputToken.balance}
                  </Text>
                )}
              </Group>
              <Group gap="md">
                <NumberInput
                  placeholder="0.0"
                  value={inputAmount}
                  onChange={(value) => setInputAmount(value.toString())}
                  min={0}
                  decimalScale={6}
                  hideControls
                  size="lg"
                  styles={{
                    input: {
                      fontSize: '1.5rem',
                      fontWeight: 600,
                      border: 'none',
                      padding: 0,
                    },
                  }}
                  style={{ flex: 1 }}
                />
                <Select
                  value={inputToken?.address}
                  onChange={(value) => {
                    const token = tokens.find((t) => t.address === value);
                    if (token) setInputToken(token);
                  }}
                  data={tokenOptions}
                  searchable
                  size="md"
                  styles={{
                    input: {
                      fontWeight: 600,
                      minWidth: '140px',
                    },
                  }}
                />
              </Group>
            </Stack>

            {/* Switch Button */}
            <Center>
              <ActionIcon
                size="lg"
                radius="xl"
                variant="light"
                onClick={handleSwitchTokens}
              >
                <IconArrowsUpDown size={20} />
              </ActionIcon>
            </Center>

            {/* Output Token */}
            <Stack gap="xs">
              <Group justify="space-between">
                <Text size="xs" c="dimmed">
                  To
                </Text>
                {outputToken?.balance && (
                  <Text size="xs" c="dimmed">
                    Balance: {outputToken.balance}
                  </Text>
                )}
              </Group>
              <Group gap="md">
                <NumberInput
                  placeholder="0.0"
                  value={outputAmount}
                  readOnly
                  min={0}
                  decimalScale={6}
                  hideControls
                  size="lg"
                  styles={{
                    input: {
                      fontSize: '1.5rem',
                      fontWeight: 600,
                      border: 'none',
                      padding: 0,
                    },
                  }}
                  style={{ flex: 1 }}
                  rightSection={loading && <Loader size="xs" />}
                />
                <Select
                  value={outputToken?.address}
                  onChange={(value) => {
                    const token = tokens.find((t) => t.address === value);
                    if (token) setOutputToken(token);
                  }}
                  data={tokenOptions}
                  searchable
                  size="md"
                  styles={{
                    input: {
                      fontWeight: 600,
                      minWidth: '140px',
                    },
                  }}
                />
              </Group>
            </Stack>

            {/* Quote Details */}
            {quote && (
              <>
                <Divider />
                <Stack gap="xs">
                  <Group justify="space-between">
                    <Text size="sm" c="dimmed">
                      Rate
                    </Text>
                    <Text size="sm">
                      1 {inputToken?.symbol} ={' '}
                      {(
                        parseFloat(quote.outputAmount) / parseFloat(quote.inputAmount)
                      ).toFixed(6)}{' '}
                      {outputToken?.symbol}
                    </Text>
                  </Group>
                  <Group justify="space-between">
                    <Text size="sm" c="dimmed">
                      Price Impact
                    </Text>
                    <Badge
                      color={parseFloat(quote.priceImpact) > 5 ? 'red' : 'green'}
                      size="sm"
                    >
                      {quote.priceImpact}%
                    </Badge>
                  </Group>
                  <Group justify="space-between">
                    <Text size="sm" c="dimmed">
                      Minimum Received
                    </Text>
                    <Text size="sm">
                      {quote.minimumReceived} {outputToken?.symbol}
                    </Text>
                  </Group>
                  <Group justify="space-between">
                    <Text size="sm" c="dimmed">
                      Gas Estimate
                    </Text>
                    <Text size="sm">{quote.gasEstimate}</Text>
                  </Group>
                </Stack>
              </>
            )}

            {/* Error Alert */}
            {error && (
              <Alert
                icon={<IconAlertTriangle size={16} />}
                title="Error"
                color="red"
                variant="light"
              >
                {error}
              </Alert>
            )}

            {/* Swap Button */}
            <Button
              size="lg"
              fullWidth
              onClick={handleSwap}
              disabled={!quote || loading || swapping}
              loading={swapping}
              leftSection={<IconRefresh size={20} />}
            >
              {swapping ? 'Swapping...' : 'Swap'}
            </Button>
          </Stack>
        </Card>

        {/* Result */}
        {result && (
          <Alert
            icon={<IconCheck size={16} />}
            title="Swap Successful"
            color="green"
            variant="light"
          >
            <Stack gap="xs">
              <Text size="sm">
                Swapped {result.inputAmount} {result.inputToken.symbol} for{' '}
                {result.outputAmount} {result.outputToken.symbol}
              </Text>
              <Group gap="xs">
                <Text size="xs" c="dimmed">
                  Transaction:
                </Text>
                <Text size="xs" fw={500}>
                  {result.txHash.slice(0, 10)}...{result.txHash.slice(-8)}
                </Text>
              </Group>
            </Stack>
          </Alert>
        )}

        {/* Network Badge */}
        <Center>
          <Badge variant="light" size="lg">
            {chain} {network}
          </Badge>
        </Center>
      </Stack>
    </Container>
  );
}
