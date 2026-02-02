# Strategy Defaults (v0)

These are *starting points* for “stable but frequent monitoring”.

## Ranking

- Use `solana_meteora_dlmm_rank_pairs` with:
  - `filter=all`
  - `limit=50`

If the API provides `volume_24h`, rank by that; otherwise fall back to fee/trades.

## Filters (conservative)

- Exclude pools tagged:
  - `very_low_liquidity`
- Prefer pools with:
  - **tvl/liquidity >= 1,000,000 USD**

## Monitoring cadence

- Interval: every **5 minutes**.
- Only alert when one of these changes materially:
  - fee/tvl ratio crosses threshold
  - tvl drops below floor
  - volume spikes sharply (24h proxy) — see triggers below

## Triggers (mode B: fee/volume-driven)

Pick candidates from the **top 50** ranked pools.

Recommended triggers (v0):
- **Min TVL gate:** skip if tvl < 1,000,000 USD.
- **Fee/TvL ratio:** alert if (fee_24h / tvl) >= 1%.
- **Volume spike:** alert if volume_24h is in the top 10 AND tvl gate passes.

Notes:
- These triggers are intentionally simple. They bias toward liquid pools but still react to high fee regimes.

## Execution

- Always build pending confirmations.
- Human approves confirm step (mainnet safety).
