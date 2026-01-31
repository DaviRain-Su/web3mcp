# Local zkLogin Prover (Docker)

This runs a local zkLogin prover using Mysten's Docker images. It is suitable for development and testing when you don't have Enoki access.

## Prereqs

- Docker Desktop
- Git LFS (for downloading the zkey)

## Download the zkey

Mainnet/Testnet zkey:

```bash
wget -O - https://raw.githubusercontent.com/sui-foundation/zklogin-ceremony-contributions/main/download-main-zkey.sh | bash
```

Testnet zkey:

```bash
wget -O - https://raw.githubusercontent.com/sui-foundation/zklogin-ceremony-contributions/main/download-test-zkey.sh | bash
```

This will download `zkLogin-main.zkey`.

## Run the prover

```bash
cp .env.example .env
# set ZKEY to the absolute path of zkLogin-main.zkey
docker compose up
```

When it's ready, the prover is available at:

```
http://localhost:8080/v1
```

Ping check:

```
curl http://localhost:8080/ping
```

## Notes

- The backend prover is CPU heavy; expect a few seconds per request.
- If you need more time per request, set `PROVER_TIMEOUT` in the compose file.
- On Apple Silicon, Docker runs the prover image under x86_64 emulation. If you see `Illegal instruction`, ensure Docker Desktop has Rosetta enabled or run the prover on an x86_64 host.
