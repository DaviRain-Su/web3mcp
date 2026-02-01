# Permit2 selectors (notes)

Permit2 (Uniswap) has multiple entrypoints.

Common ones we care about:
- transferFrom(address from,address to,uint160 amount,address token) => 0x36c78516 (handled)
- permit(address owner, PermitSingle permitSingle, bytes signature) => 0x2b67b570
- permit(address owner, PermitBatch permitBatch, bytes signature) => 0x2a2d80d1

This file is a placeholder to track additional selectors.
