#!/usr/bin/env bash
#
# Exercises the real entrypoint.sh against stubbed 0.4.0 binaries. No Docker, no
# root, no TUN — this covers the control flow only, which is where the version
# differences bite: who wins the reopen race, and what SIGTERM does to the saved
# room. The relay and the gate still need a live smoke test.
#
#   ./run.sh              # all cases, default timing
#   FAKE_RESOLVE_DELAY=0 ./run.sh   # daemon wins the reopen race
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
SRC="$HERE/../entrypoint.sh"
BIN="$HERE/stubs"
WORK="${WORK:-/tmp/kanpachi-sidecar-test}"

cat > "$BIN/socat" <<'EOF'
#!/usr/bin/env bash
echo "[stub socat] $*" >&2
sleep 3600
EOF
chmod +x "$BIN"/socat "$BIN"/kanpachi "$BIN"/kanpachid

fail=0

run_case() {
  local name="$1" seeded="$2" reopen="${3:-connected}" want_exit="$4" want_saved="$5"
  local dir="$WORK/$name"
  rm -rf "$dir"; mkdir -p "$dir/run" "$dir/state" "$dir/shared"
  [ "$seeded" = seeded ] && echo '{"name":"Merwebo Zomboid"}' > "$dir/state/hosted-room.json"

  # Only the absolute daemon path is rewritten; the logic is untouched.
  sed "s#/usr/libexec/kanpachi/kanpachid#$BIN/kanpachid#" "$SRC" > "$dir/entrypoint.sh"
  chmod +x "$dir/entrypoint.sh"

  echo "════════ $name ════════"
  (
    export PATH="$BIN:$PATH"
    export KANPACHI_RUN_DIR="$dir/run" KANPACHI_STATE_DIR="$dir/state" SHARED_DIR="$dir/shared"
    export KANPACHI_SEED=example.invalid KANPACHI_SEED_PASSWORD=stub
    export FAKE_REOPEN_RESULT="$reopen" FAKE_RESOLVE_DELAY="${FAKE_RESOLVE_DELAY:-1}"
    # exec, so SIGTERM reaches the script and not a wrapper subshell.
    exec "$dir/entrypoint.sh"
  ) > "$dir/out.log" 2>&1 &
  local pid=$!

  for _ in $(seq 1 60); do
    grep -q 'relaying udp\|refusing to start a relay' "$dir/out.log" 2>/dev/null && break
    kill -0 $pid 2>/dev/null || break
    sleep 0.5
  done
  kill -TERM $pid 2>/dev/null
  wait $pid 2>/dev/null; local rc=$?

  sed 's/^/    /' "$dir/out.log"
  local saved=gone
  [ -f "$dir/state/hosted-room.json" ] && saved=survived

  if [ "$rc" = "$want_exit" ] && [ "$saved" = "$want_saved" ]; then
    echo "    ✓ exit=$rc saved-room=$saved"
  else
    echo "    ✗ exit=$rc (want $want_exit)  saved-room=$saved (want $want_saved)"
    fail=1
  fi
  echo
}

#         name                        state    reopen      exit  saved-room
run_case "first-start-no-saved-room"  fresh    connected   0     survived
run_case "restart-saved-room"         seeded   connected   0     survived
run_case "restart-reopen-failed"      seeded   idle        0     survived

[ "$fail" = 0 ] && echo "all cases passed" || { echo "FAILURES"; exit 1; }
