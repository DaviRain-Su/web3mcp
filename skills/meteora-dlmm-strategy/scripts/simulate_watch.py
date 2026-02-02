#!/usr/bin/env python3
"""Meteora DLMM strategy simulator (off-chain).

Purpose:
- Fetch Meteora DLMM pair list from dlmm-api
- Adaptively detect fee/volume/tvl fields
- Rank top N (default 50)
- Filter by tvl >= 1,000,000
- Trigger mode B:
  - fee/tvl >= 1%
  - OR volume top10 (within topN) and tvl gate passes
- Apply cooldown (default 15 minutes) per pair
- Estimate fee share for a hypothetical investment: fee_24h * (invest_usd / tvl)

This is a *heuristic simulator* (no on-chain state, no IL modeling).
"""

from __future__ import annotations

import argparse
import json
import os
import time
from typing import Any, Dict, Optional, Tuple, List

try:
    import requests  # type: ignore
except Exception:
    requests = None
    import urllib.request


def now_ms() -> int:
    return int(time.time() * 1000)


def first_number(obj: Dict[str, Any], keys: List[str]) -> Optional[Tuple[float, str]]:
    for k in keys:
        if k in obj and obj[k] is not None:
            v = obj[k]
            if isinstance(v, (int, float)):
                return float(v), k
            if isinstance(v, str):
                try:
                    return float(v.strip()), k
                except Exception:
                    pass
    return None


def first_string(obj: Dict[str, Any], keys: List[str]) -> Optional[Tuple[str, str]]:
    for k in keys:
        if k in obj and obj[k] is not None:
            v = obj[k]
            if isinstance(v, str) and v.strip():
                return v.strip(), k
    return None


def http_get_json(url: str, timeout_s: int = 15) -> Any:
    if requests is not None:
        r = requests.get(url, timeout=timeout_s)
        r.raise_for_status()
        return r.json()

    with urllib.request.urlopen(url, timeout=timeout_s) as resp:
        data = resp.read().decode("utf-8")
        return json.loads(data)


def load_state(path: str) -> Dict[str, Any]:
    if not os.path.exists(path):
        return {"last_alert_ms": {}}
    try:
        with open(path, "r", encoding="utf-8") as f:
            return json.load(f)
    except Exception:
        return {"last_alert_ms": {}}


def save_state(path: str, state: Dict[str, Any]) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False, indent=2)
    os.replace(tmp, path)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", default=os.environ.get("SOLANA_METEORA_DLMM_API_BASE_URL", "https://dlmm-api.meteora.ag"))
    ap.add_argument("--top-n", type=int, default=50)
    ap.add_argument("--limit", type=int, default=50, help="alias for --top-n")
    ap.add_argument("--min-tvl", type=float, default=1_000_000.0)
    ap.add_argument("--cooldown-min", type=int, default=15)
    ap.add_argument("--invest-usd", type=float, default=10_000.0)
    ap.add_argument("--state", default=os.path.join(os.path.dirname(__file__), "..", "state", "watch_state.json"))
    ap.add_argument("--json", action="store_true", help="emit machine-readable JSON")
    ap.add_argument(
        "--include-ranked",
        action="store_true",
        help="include the full ranked top-N list (with mint_x/mint_y) in JSON output",
    )
    args = ap.parse_args()

    top_n = args.top_n if args.top_n else args.limit

    url = args.base_url.rstrip("/") + "/pair/all"
    pairs = http_get_json(url)
    if not isinstance(pairs, list):
        raise SystemExit(f"Unexpected /pair/all response (expected array), got: {type(pairs)}")

    fee_keys = ["fee24h", "fees24h", "fees_24h", "fee_24h", "fee_24_hours", "fees_24_hours"]
    volume_keys = ["volume24h", "volume_24h", "volume_24_hours", "volume24H"]
    tvl_keys = ["tvl", "liquidity", "liquidity_usd", "tvl_usd", "tvlUsd", "liquidityUsd"]
    addr_keys = ["address", "pair_address", "pairAddress", "lbPair", "poolAddress", "pool_address"]
    mintx_keys = ["mint_x", "mintX", "tokenXMint", "token_x_mint", "token0Mint", "token0_mint"]
    minty_keys = ["mint_y", "mintY", "tokenYMint", "token_y_mint", "token1Mint", "token1_mint"]

    rows = []
    diag = {"fee": None, "volume": None, "tvl": None, "addr": None, "mint_x": None, "mint_y": None}

    for p in pairs:
        if not isinstance(p, dict):
            continue

        addr = first_string(p, addr_keys)
        mint_x = first_string(p, mintx_keys)
        mint_y = first_string(p, minty_keys)
        fee = first_number(p, fee_keys)
        vol = first_number(p, volume_keys)
        tvl = first_number(p, tvl_keys)

        if diag["addr"] is None and addr:
            diag["addr"] = addr[1]
        if diag["mint_x"] is None and mint_x:
            diag["mint_x"] = mint_x[1]
        if diag["mint_y"] is None and mint_y:
            diag["mint_y"] = mint_y[1]
        if diag["fee"] is None and fee:
            diag["fee"] = fee[1]
        if diag["volume"] is None and vol:
            diag["volume"] = vol[1]
        if diag["tvl"] is None and tvl:
            diag["tvl"] = tvl[1]

        fee_v = fee[0] if fee else None
        vol_v = vol[0] if vol else None
        tvl_v = tvl[0] if tvl else None

        score = fee_v if fee_v is not None else (vol_v if vol_v is not None else (tvl_v if tvl_v is not None else 0.0))

        rows.append({
            "pair_address": addr[0] if addr else None,
            "mint_x": mint_x[0] if mint_x else None,
            "mint_y": mint_y[0] if mint_y else None,
            "fee_24h": fee_v,
            "volume_24h": vol_v,
            "tvl": tvl_v,
            "score": score,
        })

    rows.sort(key=lambda r: (r.get("score") or 0.0), reverse=True)
    ranked = rows[:top_n]

    # Volume top 10 among the ranked list
    vol_sorted = sorted(
        [r for r in ranked if isinstance(r.get("volume_24h"), (int, float))],
        key=lambda r: r.get("volume_24h") or 0.0,
        reverse=True,
    )
    top10_vol_addrs = set([r.get("pair_address") for r in vol_sorted[:10] if r.get("pair_address")])

    state = load_state(args.state)
    last_alert_ms = state.get("last_alert_ms", {})

    cooldown_ms = args.cooldown_min * 60 * 1000
    min_tvl = float(args.min_tvl)

    alerts = []
    for r in ranked:
        addr = r.get("pair_address")
        if not addr:
            continue

        tvl = r.get("tvl")
        if not isinstance(tvl, (int, float)) or tvl < min_tvl:
            continue

        fee = r.get("fee_24h")
        vol = r.get("volume_24h")

        fee_tvl = None
        if isinstance(fee, (int, float)) and tvl > 0:
            fee_tvl = float(fee) / float(tvl)

        trigger_fee_tvl = fee_tvl is not None and fee_tvl >= 0.01
        trigger_vol = addr in top10_vol_addrs

        if not (trigger_fee_tvl or trigger_vol):
            continue

        last = int(last_alert_ms.get(addr, 0) or 0)
        if now_ms() - last < cooldown_ms:
            continue

        est_fee_share = None
        if isinstance(fee, (int, float)) and tvl > 0:
            est_fee_share = float(fee) * (float(args.invest_usd) / float(tvl))

        alerts.append({
            "pair_address": addr,
            "mint_x": r.get("mint_x"),
            "mint_y": r.get("mint_y"),
            "fee_24h": fee,
            "volume_24h": vol,
            "tvl": tvl,
            "fee_over_tvl": fee_tvl,
            "trigger": {
                "fee_over_tvl_ge_1pct": trigger_fee_tvl,
                "top10_volume": trigger_vol,
            },
            "invest_usd": args.invest_usd,
            "est_fee_share_24h_usd": est_fee_share,
        })

        last_alert_ms[addr] = now_ms()

    state["last_alert_ms"] = last_alert_ms
    save_state(args.state, state)

    out = {
        "source": {"url": url, "count": len(pairs)},
        "ranked": {
            "top_n": top_n,
            "min_tvl": min_tvl,
            "cooldown_min": args.cooldown_min,
            "invest_usd": args.invest_usd,
        },
        "field_diagnostics": diag,
        "alerts": alerts,
    }

    if args.include_ranked:
        out["ranked"]["pairs"] = ranked

    if args.json:
        print(json.dumps(out, ensure_ascii=False))
    else:
        print(f"Meteora DLMM watch: top_n={top_n}, min_tvl={min_tvl:.0f}, cooldown={args.cooldown_min}min, invest_usd={args.invest_usd:.0f}")
        print(f"Detected fields: fee={diag['fee']} volume={diag['volume']} tvl={diag['tvl']} addr={diag['addr']} mX={diag['mint_x']} mY={diag['mint_y']}")
        if not alerts:
            print("No alerts.")
        else:
            print(f"Alerts: {len(alerts)}")
            for a in alerts[:10]:
                fee_tvl = a.get("fee_over_tvl")
                fee_tvl_s = f"{fee_tvl*100:.2f}%" if isinstance(fee_tvl, (int, float)) else "n/a"
                est = a.get("est_fee_share_24h_usd")
                est_s = f"{est:.2f}" if isinstance(est, (int, float)) else "n/a"
                print(f"- {a['pair_address']} tvl={a['tvl']:.0f} fee/tvl={fee_tvl_s} est_fee_24h~${est_s}")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
