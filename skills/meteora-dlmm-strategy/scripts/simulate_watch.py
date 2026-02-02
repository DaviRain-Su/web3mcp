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

TOKEN_LIST_DEFAULT_URL = "https://token.jup.ag/all"
TOKEN_LIST_FALLBACK_URLS = [
    # Jupiter token list (fast, usually enough)
    "https://token.jup.ag/all",
    # solana-labs token list (fallback)
    "https://raw.githubusercontent.com/solana-labs/token-list/main/src/tokens/solana.tokenlist.json",
]

# Common stable mints (mainnet)
STABLE_MINTS = {
    "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v",  # USDC
    "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB",  # USDT
}

# Bluechip assets to optionally exclude from meme focus.
BLUECHIP_MINTS = {
    # SOL
    "So11111111111111111111111111111111111111112",
    # wBTC (Solana)
    "qfnqNqs3j7yKpQ7J1xY9v7xYk4J3oV1uT7u4QmKX2pT",  # placeholder; will rely on token list symbol fallback
    # wETH (Solana)
    "7vfCXTUXx5WJV5JADk17DUJ4ksgau7utNKj4b963voxs",  # ETH (Wormhole)
}


def human_usd(x: Optional[float]) -> str:
    if x is None:
        return "n/a"
    try:
        v = float(x)
    except Exception:
        return "n/a"
    av = abs(v)
    if av >= 1_000_000_000:
        return f"${v/1_000_000_000:.2f}B"
    if av >= 1_000_000:
        return f"${v/1_000_000:.2f}M"
    if av >= 1_000:
        return f"${v/1_000:.2f}K"
    return f"${v:.2f}"

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
        return {"last_alert_ms": {}, "token_cache": {}}
    try:
        with open(path, "r", encoding="utf-8") as f:
            s = json.load(f)
            if "last_alert_ms" not in s:
                s["last_alert_ms"] = {}
            if "token_cache" not in s:
                s["token_cache"] = {}
            return s
    except Exception:
        return {"last_alert_ms": {}, "token_cache": {}}


def save_state(path: str, state: Dict[str, Any]) -> None:
    dirpath = os.path.dirname(path)
    if dirpath:
        os.makedirs(dirpath, exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(state, f, ensure_ascii=False, indent=2)
    os.replace(tmp, path)


def resolve_token_map(
    state: Dict[str, Any],
    token_list_url: str,
    token_cache_ttl_ms: int,
    timeout_s: int = 45,
) -> Dict[str, Dict[str, str]]:
    """Return mapping mint-> {symbol,name}. Cached in state.

    Behavior:
    - Use cached map if fresh.
    - If stale but present, keep using it when refresh fails (better UX than dropping to 2 tokens).
    - Try multiple token list sources.
    """

    cache = state.get("token_cache") or {}
    cached_at = int(cache.get("fetched_at_ms", 0) or 0)
    by_mint = cache.get("by_mint")

    if isinstance(by_mint, dict) and by_mint and now_ms() - cached_at < token_cache_ttl_ms:
        return by_mint

    urls = [token_list_url] + [u for u in TOKEN_LIST_FALLBACK_URLS if u != token_list_url]

    def minimal_fallback() -> Dict[str, Dict[str, str]]:
        return {
            "So11111111111111111111111111111111111111112": {
                "symbol": "SOL",
                "name": "Wrapped SOL",
            },
            "EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v": {
                "symbol": "USDC",
                "name": "USD Coin",
            },
            "Es9vMFrzaCERmJfrF4H2FYD4KCoNkY11McCe8BenwNYB": {
                "symbol": "USDT",
                "name": "Tether USD",
            },
        }

    for u in urls:
        try:
            data = http_get_json(u, timeout_s=timeout_s)

            m: Dict[str, Dict[str, str]] = {}
            if isinstance(data, list):
                # Jupiter format
                for t in data:
                    if not isinstance(t, dict):
                        continue
                    addr = t.get("address")
                    sym = t.get("symbol")
                    name = t.get("name")
                    if isinstance(addr, str) and addr and isinstance(sym, str) and sym:
                        m[addr] = {
                            "symbol": sym,
                            "name": name if isinstance(name, str) else sym,
                        }
            elif isinstance(data, dict) and isinstance(data.get("tokens"), list):
                # solana-labs token-list format
                for t in data.get("tokens"):
                    if not isinstance(t, dict):
                        continue
                    addr = t.get("address")
                    sym = t.get("symbol")
                    name = t.get("name")
                    if isinstance(addr, str) and addr and isinstance(sym, str) and sym:
                        m[addr] = {
                            "symbol": sym,
                            "name": name if isinstance(name, str) else sym,
                        }

            if m:
                state["token_cache"] = {
                    "fetched_at_ms": now_ms(),
                    "url": u,
                    "by_mint": m,
                }
                return m
        except Exception:
            continue

    # If refresh failed but we have an old cache, keep using it.
    if isinstance(by_mint, dict) and by_mint:
        return by_mint

    return minimal_fallback()

def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--base-url", default=os.environ.get("SOLANA_METEORA_DLMM_API_BASE_URL", "https://dlmm-api.meteora.ag"))
    ap.add_argument(
        "--enrich-details",
        action="store_true",
        help="fetch /pair/<address> for top-N candidates to enrich volume/trade_volume and other fields",
    )
    ap.add_argument(
        "--window",
        default="24h",
        choices=["24h", "12h", "4h", "2h", "1h", "30m"],
        help="window for volume-based scoring (requires --enrich-details). default: 24h",
    )
    ap.add_argument("--top-n", type=int, default=50)
    ap.add_argument(
        "--trigger-fee-tvl-window-min",
        type=float,
        default=None,
        help="trigger if fee_tvl_ratio over selected window >= this percent (e.g. 0.6 for 0.6%). Requires --enrich-details.",
    )
    ap.add_argument(
        "--trigger-score-top",
        type=int,
        default=None,
        help="trigger if pair is within top K by score (fee/vol on selected window).",
    )
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
    ap.add_argument(
        "--token-list-url",
        default=TOKEN_LIST_DEFAULT_URL,
        help="token list URL (mint->symbol/name), default: https://token.jup.ag/all",
    )
    ap.add_argument(
        "--focus",
        default="all",
        choices=["all", "meme"],
        help="pool focus: all (default) or meme (exclude stable pairs; keep non-stable long-tail)",
    )
    ap.add_argument(
        "--exclude-bluechip",
        action="store_true",
        help="when --focus=meme, also exclude bluechip pairs like SOL/ETH/BTC",
    )
    ap.add_argument(
        "--token-cache-ttl-min",
        type=int,
        default=720,
        help="token list cache TTL (minutes), default 720 (12h)",
    )
    args = ap.parse_args()

    top_n = args.top_n if args.top_n else args.limit

    url = args.base_url.rstrip("/") + "/pair/all"
    # /pair/all can be large; allow longer timeout than default. Retry a few times.
    fetch_started = now_ms()
    last_fetch_error = None
    pairs = None
    for attempt in range(1, 4):
        try:
            pairs = http_get_json(url, timeout_s=45)
            last_fetch_error = None
            break
        except Exception as e:
            last_fetch_error = str(e)
            time.sleep(0.8 * attempt)
    fetch_duration_ms = now_ms() - fetch_started
    if pairs is None:
        raise SystemExit(f"Failed to fetch {url}: {last_fetch_error}")
    if not isinstance(pairs, list):
        raise SystemExit(f"Unexpected /pair/all response (expected array), got: {type(pairs)}")

    fee_keys = ["fee24h", "fees24h", "fees_24h", "fee_24h", "fee_24_hours", "fees_24_hours"]
    volume_keys = [
        "volume24h",
        "volume_24h",
        "volume_24_hours",
        "volume24H",
        "volume",
        "volume_usd",
        "volumeUsd",
    ]
    trades_keys = [
        "trade24h",
        "trades24h",
        "trades_24h",
        "txn24h",
        "txns24h",
        "txCount24h",
    ]
    tvl_keys = ["tvl", "liquidity", "liquidity_usd", "tvl_usd", "tvlUsd", "liquidityUsd"]
    addr_keys = ["address", "pair_address", "pairAddress", "lbPair", "poolAddress", "pool_address"]
    mintx_keys = ["mint_x", "mintX", "tokenXMint", "token_x_mint", "token0Mint", "token0_mint"]
    minty_keys = ["mint_y", "mintY", "tokenYMint", "token_y_mint", "token1Mint", "token1_mint"]

    rows = []
    diag = {
        "fee": None,
        "volume": None,
        "trades": None,
        "tvl": None,
        "addr": None,
        "mint_x": None,
        "mint_y": None,
    }

    for p in pairs:
        if not isinstance(p, dict):
            continue

        addr = first_string(p, addr_keys)
        mint_x = first_string(p, mintx_keys)
        mint_y = first_string(p, minty_keys)
        fee = first_number(p, fee_keys)
        vol = first_number(p, volume_keys)
        trades = first_number(p, trades_keys)
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
        if diag["trades"] is None and trades:
            diag["trades"] = trades[1]
        if diag["tvl"] is None and tvl:
            diag["tvl"] = tvl[1]

        fee_v = fee[0] if fee else None
        vol_v = vol[0] if vol else None
        trades_v = trades[0] if trades else None
        tvl_v = tvl[0] if tvl else None

        # Initial score before enrichment: use fee_24h so we can pick candidates,
        # then (optionally) re-rank after details enrichment.
        score = fee_v if fee_v is not None else 0.0

        fee_over_tvl = float(fee_v) / float(tvl_v) if (fee_v is not None and tvl_v) else None

        rows.append({
            "pair_address": addr[0] if addr else None,
            "mint_x": mint_x[0] if mint_x else None,
            "mint_y": mint_y[0] if mint_y else None,
            "fee_24h": fee_v,
            "volume_24h": vol_v,
            "trades_24h": trades_v,
            "tvl": tvl_v,
            "fee_over_tvl": fee_over_tvl,
            "score": score,
        })

    # Deterministic ordering: tie-break by pair_address.
    rows.sort(
        key=lambda r: (
            -(float(r.get("score") or 0.0)),
            str(r.get("pair_address") or ""),
        )
    )
    ranked = rows[:top_n]

    # Optional: enrich candidates via /pair/<address> (gives volume buckets + fee_tvl_ratio buckets, base_fee_percentage, etc.)
    if args.enrich_details:
        window_key_map = {
            "30m": "min_30",
            "1h": "hour_1",
            "2h": "hour_2",
            "4h": "hour_4",
            "12h": "hour_12",
            "24h": "hour_24",
        }
        wkey = window_key_map.get(args.window, "hour_24")

        for r in ranked:
            addr = r.get("pair_address")
            if not isinstance(addr, str) or not addr:
                continue
            try:
                detail = http_get_json(f"{args.base_url.rstrip('/')}/pair/{addr}", timeout_s=20)
                if isinstance(detail, dict):
                    # 1) Volume: prefer bucketed detail.volume[wkey]; fallback to trade_volume_24h
                    vol = detail.get("volume")
                    if isinstance(vol, dict) and isinstance(vol.get(wkey), (int, float)):
                        r["volume_window"] = float(vol.get(wkey))
                    else:
                        tv24 = detail.get("trade_volume_24h")
                        if isinstance(tv24, (int, float)):
                            r["volume_window"] = float(tv24)

                    # 2) Fee estimate for window: use fee_tvl_ratio bucket * tvl
                    # fee_tvl_ratio appears to be a percent value (e.g. 1.59 = 1.59%)
                    ftr = detail.get("fee_tvl_ratio")
                    if isinstance(ftr, dict) and isinstance(ftr.get(wkey), (int, float)):
                        r["fee_tvl_ratio_window"] = float(ftr.get(wkey))
                    else:
                        r["fee_tvl_ratio_window"] = None

                    tvl = r.get("tvl")
                    if isinstance(tvl, (int, float)) and tvl > 0 and isinstance(r.get("fee_tvl_ratio_window"), (int, float)):
                        r["fee_window"] = float(tvl) * (float(r["fee_tvl_ratio_window"]) / 100.0)
                    else:
                        r["fee_window"] = None

                    r["base_fee_percentage"] = detail.get("base_fee_percentage")
                    r["max_fee_percentage"] = detail.get("max_fee_percentage")
            except Exception:
                continue

        # Re-rank after enrichment using fee/vol on selected window
        for r in ranked:
            fee = r.get("fee_window") if isinstance(r.get("fee_window"), (int, float)) else r.get("fee_24h")
            vol = r.get("volume_window") if isinstance(r.get("volume_window"), (int, float)) else r.get("volume_24h")
            if isinstance(fee, (int, float)) and isinstance(vol, (int, float)) and vol > 0:
                r["fee_over_vol"] = float(fee) / float(vol)
                r["score"] = r["fee_over_vol"]
            else:
                r["fee_over_vol"] = None
                # fallback score: fee/tvl if possible else fee
                tvl = r.get("tvl")
                if isinstance(fee, (int, float)) and isinstance(tvl, (int, float)) and tvl > 0:
                    r["score"] = float(fee) / float(tvl)
                elif isinstance(fee, (int, float)):
                    r["score"] = float(fee)
                else:
                    r["score"] = 0.0

        ranked.sort(
            key=lambda r: (
                -(float(r.get("score") or 0.0)),
                str(r.get("pair_address") or ""),
            )
        )

    # Volume top 10 among the ranked list (uses enriched window volume when available)
    vol_sorted = sorted(
        [r for r in ranked if isinstance(r.get("volume_window"), (int, float))],
        key=lambda r: (-(float(r.get("volume_window") or 0.0)), str(r.get("pair_address") or "")),
    )
    trades_sorted = sorted(
        [r for r in ranked if isinstance(r.get("trades_24h"), (int, float))],
        key=lambda r: (-(float(r.get("trades_24h") or 0.0)), str(r.get("pair_address") or "")),
    )

    top10_vol_addrs = set(
        [r.get("pair_address") for r in vol_sorted[:10] if r.get("pair_address")]
    )
    top10_trades_addrs = set(
        [r.get("pair_address") for r in trades_sorted[:10] if r.get("pair_address")]
    )

    trigger_score_top_addrs: set[str] = set()
    if isinstance(args.trigger_score_top, int) and args.trigger_score_top > 0:
        trigger_score_top_addrs = set(
            [r.get("pair_address") for r in ranked[: args.trigger_score_top] if r.get("pair_address")]
        )

    state = load_state(args.state)
    last_alert_ms = state.get("last_alert_ms", {})

    token_cache_ttl_ms = args.token_cache_ttl_min * 60 * 1000
    token_map = resolve_token_map(state, args.token_list_url, token_cache_ttl_ms)
    token_cache = state.get("token_cache") or {}
    token_source_url = token_cache.get("url")
    token_cached_at_ms = token_cache.get("fetched_at_ms")

    # Apply focus filter (e.g. meme) AFTER ranking, but before trigger evaluation.
    if args.focus == "meme":
        def is_meme_pair(r: Dict[str, Any]) -> bool:
            mx = r.get("mint_x")
            my = r.get("mint_y")
            if not isinstance(mx, str) or not isinstance(my, str):
                return True

            # 1) Hard exclude stablecoin participation
            if mx in STABLE_MINTS or my in STABLE_MINTS:
                return False

            # 2) Optionally exclude obvious bluechips (SOL/ETH/BTC-like)
            if args.exclude_bluechip:
                # Use mint set first
                if mx in BLUECHIP_MINTS or my in BLUECHIP_MINTS:
                    return False
                # Also use symbol if available
                mxs = (r.get("mint_x_symbol") or "").upper()
                mys = (r.get("mint_y_symbol") or "").upper()
                if mxs in ("SOL", "ETH", "BTC", "WBTC", "WETH"):
                    return False
                if mys in ("SOL", "ETH", "BTC", "WBTC", "WETH"):
                    return False

            # Keep everything else (non-stable long-tail, including non-pump memes)
            return True

        ranked = [r for r in ranked if is_meme_pair(r)]

    # Enrich ranked entries with symbols/labels (used by cron summaries)
    for r in ranked:
        mx = r.get("mint_x")
        my = r.get("mint_y")
        mx_sym = token_map.get(mx, {}).get("symbol") if isinstance(mx, str) else None
        my_sym = token_map.get(my, {}).get("symbol") if isinstance(my, str) else None
        r["mint_x_symbol"] = mx_sym
        r["mint_y_symbol"] = my_sym
        r["pair_label"] = f"{mx_sym}/{my_sym}" if mx_sym and my_sym else None
        r["tvl_display"] = human_usd(r.get("tvl") if isinstance(r.get("tvl"), (int, float)) else None)
        r["fee_24h_display"] = human_usd(r.get("fee_24h") if isinstance(r.get("fee_24h"), (int, float)) else None)
        r["volume_24h_display"] = human_usd(r.get("volume_24h") if isinstance(r.get("volume_24h"), (int, float)) else None)
        r["volume_window_display"] = human_usd(r.get("volume_window") if isinstance(r.get("volume_window"), (int, float)) else None)
        r["fee_window_display"] = human_usd(r.get("fee_window") if isinstance(r.get("fee_window"), (int, float)) else None)

    cooldown_ms = args.cooldown_min * 60 * 1000
    min_tvl = float(args.min_tvl)

    eligible_after_tvl = 0
    triggered_before_cooldown = 0
    suppressed_by_cooldown = 0
    triggers_count = {
        "fee_over_tvl_ge_1pct": 0,
        "fee_tvl_window_ge_threshold": 0,
        "score_topk": 0,
        "top10_volume": 0,
        "top10_trades": 0,
    }

    alerts = []
    for r in ranked:
        addr = r.get("pair_address")
        if not addr:
            continue

        tvl = r.get("tvl")
        if not isinstance(tvl, (int, float)) or tvl < min_tvl:
            continue

        eligible_after_tvl += 1

        fee = r.get("fee_24h")
        vol = r.get("volume_24h")
        trades = r.get("trades_24h")

        fee_tvl = None
        if isinstance(fee, (int, float)) and tvl > 0:
            fee_tvl = float(fee) / float(tvl)

        # Window-specific fee/tvl ratio (percent) from enrichment, e.g. 0.6 means 0.6%
        fee_tvl_ratio_window = r.get("fee_tvl_ratio_window")
        if not isinstance(fee_tvl_ratio_window, (int, float)):
            fee_tvl_ratio_window = None

        trigger_fee_tvl = fee_tvl is not None and fee_tvl >= 0.01
        trigger_fee_tvl_window = False
        if args.trigger_fee_tvl_window_min is not None:
            trigger_fee_tvl_window = (
                fee_tvl_ratio_window is not None
                and float(fee_tvl_ratio_window) >= float(args.trigger_fee_tvl_window_min)
            )

        trigger_vol = addr in top10_vol_addrs
        trigger_trades = addr in top10_trades_addrs
        trigger_score_top = addr in trigger_score_top_addrs

        if not (trigger_fee_tvl or trigger_fee_tvl_window or trigger_vol or trigger_trades or trigger_score_top):
            continue

        triggered_before_cooldown += 1
        if trigger_fee_tvl:
            triggers_count["fee_over_tvl_ge_1pct"] += 1
        if trigger_fee_tvl_window:
            triggers_count["fee_tvl_window_ge_threshold"] += 1
        if trigger_score_top:
            triggers_count["score_topk"] += 1
        if trigger_vol:
            triggers_count["top10_volume"] += 1
        if trigger_trades:
            triggers_count["top10_trades"] += 1

        last = int(last_alert_ms.get(addr, 0) or 0)
        if now_ms() - last < cooldown_ms:
            suppressed_by_cooldown += 1
            continue

        est_fee_share = None
        if isinstance(fee, (int, float)) and tvl > 0:
            est_fee_share = float(fee) * (float(args.invest_usd) / float(tvl))

        mx = r.get("mint_x")
        my = r.get("mint_y")
        mx_sym = token_map.get(mx, {}).get("symbol") if isinstance(mx, str) else None
        my_sym = token_map.get(my, {}).get("symbol") if isinstance(my, str) else None

        pair_label = None
        if mx_sym and my_sym:
            pair_label = f"{mx_sym}/{my_sym}"

        alerts.append({
            "pair_address": addr,
            "mint_x": mx,
            "mint_y": my,
            "mint_x_symbol": mx_sym,
            "mint_y_symbol": my_sym,
            "pair_label": pair_label,
            "fee_24h": fee,
            "fee_24h_display": human_usd(fee if isinstance(fee, (int, float)) else None),
            "volume_24h": vol,
            "volume_24h_display": human_usd(vol if isinstance(vol, (int, float)) else None),
            "trades_24h": trades,
            "tvl": tvl,
            "tvl_display": human_usd(tvl if isinstance(tvl, (int, float)) else None),
            "fee_over_tvl": fee_tvl,
            "fee_tvl_ratio_window": r.get("fee_tvl_ratio_window"),
            "volume_window": r.get("volume_window"),
            "fee_window": r.get("fee_window"),
            "fee_over_vol": r.get("fee_over_vol"),
            "trigger": {
                "fee_over_tvl_ge_1pct": trigger_fee_tvl,
                "fee_tvl_window_ge_threshold": trigger_fee_tvl_window,
                "score_topk": trigger_score_top,
                "top10_volume": trigger_vol,
                "top10_trades": trigger_trades,
            },
            "invest_usd": args.invest_usd,
            "est_fee_share_24h_usd": est_fee_share,
            "est_fee_share_24h_display": human_usd(est_fee_share),
        })

        last_alert_ms[addr] = now_ms()

    state["last_alert_ms"] = last_alert_ms
    save_state(args.state, state)

    volume_present = sum(
        1
        for r in ranked
        if isinstance(r.get("volume_window"), (int, float))
        and (r.get("volume_window") or 0) > 0
    )

    out = {
        "source": {
            "url": url,
            "count": len(pairs),
            "fetch_duration_ms": fetch_duration_ms,
            "fetch_error": last_fetch_error,
        },
        "ranked": {
            "top_n": top_n,
            "min_tvl": min_tvl,
            "cooldown_min": args.cooldown_min,
            "invest_usd": args.invest_usd,
            "eligible_after_tvl": eligible_after_tvl,
            "triggered_before_cooldown": triggered_before_cooldown,
            "suppressed_by_cooldown": suppressed_by_cooldown,
            "triggers_count": triggers_count,
            "volume_window_present": volume_present,
            "window": args.window,
            "scoring": "fee_over_vol(window) (fallback fee_over_tvl, then fee)",
            "trigger": {
                "fee_tvl_window_min": args.trigger_fee_tvl_window_min,
                "score_top": args.trigger_score_top,
            },
        },
        "token_list": {
            "url": token_source_url,
            "cached_at_ms": token_cached_at_ms,
            "map_size": len(token_map),
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
        if state.get('token_cache', {}).get('url'):
            print(f"Token list: {state.get('token_cache', {}).get('url')} (cached)")
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
