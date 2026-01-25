#!/usr/bin/env sh
set -eu

TARGET=${TARGET:-x86_64-linux-gnu}
OPT=${OPT:-ReleaseFast}

zig build -Dtarget="${TARGET}" -Doptimize="${OPT}"
