# Integration Repo Skeleton (draft)

When you're ready to split the ACP integration into a standalone repo, this is a suggested structure.

```
acp-web3mcp-integration/
  README.md
  prompts/
    executor/
      solana_idl_2phase.system.md
      sui_move_2phase.system.md
      evm_call_2phase.system.md
    main-agent/
      claude-desktop.template.md
  payloads/
    solana/
      plan.json
      simulate.json
      send.json
      confirm.json
    sui/
      plan.json
      simulate.json
      send.json
      confirm.json
    evm/
      plan.json
      simulate.json
      send.json
      confirm.json
  notes/
    security.md
    rollout.md
```

## Notes

- Keep all payloads strictly JSON.
- Keep executor prompts strict and deterministic.
- Keep anything involving private keys only in executor environment.
