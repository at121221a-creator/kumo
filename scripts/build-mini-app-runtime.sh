#!/usr/bin/env bash
# Build app/DshIOS/MiniApps/Runtime: React as ES modules for 我的应用 (mini apps)
# and Sucrase, which compiles their JSX and TypeScript on the phone.
# scripts/mini-app-runtime/build.mjs says how.
#
# The output is committed, so neither a local build nor Xcode Cloud runs this.
# Run it to move to another React or Sucrase: change the versions, rebuild,
# update THIRD_PARTY_NOTICES.md, and open a few apps in the simulator.
set -euo pipefail
react="18.3.1"
sucrase="3.35.1"
esbuild="0.25.10"
root="$(cd "$(dirname "$0")/.." && pwd)"
out="$root/app/DshIOS/MiniApps/Runtime"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

npm install --silent --no-audit --no-fund --ignore-scripts --prefix "$work" \
  "react@$react" "react-dom@$react" "sucrase@$sucrase" "esbuild@$esbuild" >/dev/null
node "$root/scripts/mini-app-runtime/build.mjs" "$work/node_modules/esbuild/lib/main.js" "$work/node_modules" "$out"
ls -l "$out" | awk 'NR > 1 { print "mini-app-runtime: " $NF " (" $5 " bytes)" }'
