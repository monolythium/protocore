#!/usr/bin/env bash
# release-boot-smoke.sh — release-gate smoke test for a protocore artifact.
#
# Runs against the EXACT bytes staged for cosign/publish, in two phases:
#
#   1. Feature-manifest check. `protocore release info` prints the
#      compile-time BUILD_FEATURES manifest (CARGO_CFG_FEATURE, embedded by
#      build.rs). Every feature in SMOKE_REQUIRED_FEATURES must be present,
#      and the reported crate version must equal SMOKE_EXPECT_VERSION when
#      set. This catches a mis-built artifact without booting anything.
#
#   2. Boot smoke. Scaffold a throwaway <home>, resolve the canonical
#      genesis (+ milestones, when the registry pins them) from the public
#      chain-registry, point the indexer at a real Postgres, and boot the
#      node in full (non-validator) mode. The node must clear the fail-fast
#      boot gates — AUD-0079 (zkML backend requires `sp1-verifier` on a
#      public-profile chain id), AUD-0032 (postgres indexer durability,
#      requires `indexer-postgres`), and their siblings — and reach
#      post-gate init. Pass = the postgres indexer comes up
#      ("indexer: postgres backend connected, migrations applied", which the
#      runtime only logs AFTER the boot-gate walk in Node::start) and the
#      process is still alive after a hold window. Any typed boot failure,
#      early exit, or missing marker fails the release.
#
# Release-engineering postmortem, 2026-07-02: the v0.3.2-testnet release
# binary was built without `sp1-verifier` (a release.yml feature-list edit
# replaced it with `sp1-bridge-verifier`, which does NOT imply the runtime
# zkML feature) and every fleet node crash-looped on the AUD-0079 boot gate
# at cutover. Nothing in the pipeline executed the artifact before cosign/
# publish. This script is that missing gate: a binary missing
# `indexer-postgres` or `sp1-verifier` must fail the release job, not a
# live operator.
#
# Usage:
#   scripts/release-boot-smoke.sh <path-to-protocore-binary>
#
# Environment:
#   SMOKE_REQUIRED_FEATURES  Comma-separated feature list the binary must
#                            report. Default:
#                            mdbx,indexer-postgres,mesh,sp1-bridge-verifier,sp1-verifier
#   SMOKE_EXPECT_VERSION     Optional. Assert `release info` .version equals
#                            this exactly (e.g. "0.3.2"). Empty = skip.
#   SMOKE_POSTGRES_URL       Postgres DSN for the indexer boot phase.
#                            Required unless SMOKE_SKIP_BOOT=1.
#   SMOKE_REGISTRY_NETWORK   chain-registry network slug. Default:
#                            testnet-69420.
#   SMOKE_REGISTRY_URL       Optional chain-registry base URL override
#                            (forwarded to `genesis resolve --registry-url`).
#   SMOKE_BOOT_PROBE_SECS    Max seconds to wait for the gate-pass marker.
#                            Default: 90.
#   SMOKE_HOLD_SECS          Seconds the process must stay alive after the
#                            marker (catches a fail-fast landing just after
#                            indexer init). Default: 10.
#   SMOKE_SKIP_BOOT          =1 to run the manifest phase only.
set -euo pipefail

BIN="${1:-}"
if [[ -z "$BIN" ]]; then
  echo "usage: $0 <path-to-protocore-binary>" >&2
  exit 2
fi
if [[ ! -x "$BIN" ]]; then
  echo "FAIL: $BIN is not an executable file" >&2
  exit 2
fi
BIN="$(readlink -f "$BIN")"

REQUIRED_FEATURES="${SMOKE_REQUIRED_FEATURES:-mdbx,indexer-postgres,mesh,sp1-bridge-verifier,sp1-verifier}"
EXPECT_VERSION="${SMOKE_EXPECT_VERSION:-}"
REGISTRY_NETWORK="${SMOKE_REGISTRY_NETWORK:-testnet-69420}"
BOOT_PROBE_SECS="${SMOKE_BOOT_PROBE_SECS:-90}"
HOLD_SECS="${SMOKE_HOLD_SECS:-10}"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

# --- phase 1: compile-time feature manifest --------------------------------
echo "== boot-smoke phase 1: feature manifest =="
info_json="$("$BIN" release info --output json)" \
  || fail "'protocore release info' did not run — artifact is not a working protocore binary"
echo "$info_json"

features="$(jq -er '.features' <<<"$info_json")" \
  || fail "'release info' output has no .features field"
version="$(jq -er '.version' <<<"$info_json")" \
  || fail "'release info' output has no .version field"

missing=()
IFS=',' read -ra want <<<"$REQUIRED_FEATURES"
for f in "${want[@]}"; do
  f="$(echo "$f" | tr -d '[:space:]')"
  [[ -z "$f" ]] && continue
  hit=0
  IFS=',' read -ra have <<<"$features"
  for g in "${have[@]}"; do
    [[ "$g" == "$f" ]] && hit=1 && break
  done
  [[ "$hit" == 1 ]] || missing+=("$f")
done
if (( ${#missing[@]} > 0 )); then
  fail "binary feature manifest '$features' is missing required feature(s): ${missing[*]} — \
this is the AUD-0032/AUD-0079 mis-build class; rebuild with \
'cargo build --release -p protocore --features $REQUIRED_FEATURES'"
fi
echo "OK: all required features present ($REQUIRED_FEATURES)"

if [[ -n "$EXPECT_VERSION" ]]; then
  [[ "$version" == "$EXPECT_VERSION" ]] \
    || fail "binary reports version '$version' but the release tag expects '$EXPECT_VERSION'"
  echo "OK: version $version matches expected"
fi

if [[ "${SMOKE_SKIP_BOOT:-0}" == "1" ]]; then
  echo "SMOKE_SKIP_BOOT=1 — skipping boot phase. PASS (manifest only)."
  exit 0
fi

# --- phase 2: boot smoke ----------------------------------------------------
echo "== boot-smoke phase 2: boot against the canonical registry genesis =="
POSTGRES_URL="${SMOKE_POSTGRES_URL:-}"
[[ -n "$POSTGRES_URL" ]] || fail "SMOKE_POSTGRES_URL is required for the boot phase (or set SMOKE_SKIP_BOOT=1)"

workdir="$(mktemp -d)"
home_dir="$workdir/home"
boot_log="$workdir/boot.log"
node_pid=""
cleanup() {
  if [[ -n "$node_pid" ]] && kill -0 "$node_pid" 2>/dev/null; then
    kill -TERM "$node_pid" 2>/dev/null || true
    for _ in $(seq 1 20); do
      kill -0 "$node_pid" 2>/dev/null || break
      sleep 0.5
    done
    kill -KILL "$node_pid" 2>/dev/null || true
  fi
  rm -rf "$workdir"
}
trap cleanup EXIT

"$BIN" --home "$home_dir" init testnet --no-operator \
  || fail "'protocore init testnet' failed"

# Public-profile boots require the checked-in testnet manifests
# (name-registry reserve set, oracle genesis, ...) under <home>/testnet/ —
# they ship in the mono-core source tree at testnet/. In the release job the
# source is checked out at src/; locally point SMOKE_TESTNET_MANIFEST_DIR at
# a mono-core checkout's testnet/ directory.
manifest_dir="${SMOKE_TESTNET_MANIFEST_DIR:-src/testnet}"
if [[ -d "$manifest_dir" ]]; then
  mkdir -p "$home_dir/testnet"
  cp "$manifest_dir"/* "$home_dir/testnet/" \
    || fail "failed to copy testnet manifests from $manifest_dir"
else
  echo "note: SMOKE_TESTNET_MANIFEST_DIR '$manifest_dir' not found — public-profile boot will fail if the chain requires the checked-in manifests" >&2
fi

# The runtime unseals an operator consensus seed at boot even in full
# (non-validator) mode (AUD-0029/AUD-0060 sealed keystore). Generate a
# throwaway keypair — it is NOT on the chain roster, and full mode never
# signs consensus material with it.
smoke_passphrase="smoke-$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
export PROTOCORE_KEYSTORE_PASSPHRASE="$smoke_passphrase"
"$BIN" --home "$home_dir" registry gen-operator-keys >/dev/null \
  || fail "'protocore registry gen-operator-keys' failed"

resolve_args=(--registry-network "$REGISTRY_NETWORK")
if [[ -n "${SMOKE_REGISTRY_URL:-}" ]]; then
  resolve_args+=(--registry-url "$SMOKE_REGISTRY_URL")
fi
# --no-write-peers: do NOT record the registry's fast-sync seed RPCs into
# config.toml. With seeds recorded, a fresh node spends ~60-70s in the
# pre-indexer fast-sync checkpoint retry loop (6 attempts x N seeds with
# backoff — longer over WAN, or once the fleet serves real snapshots that
# must download pre-indexer) before Node::start reaches the indexer spawn
# that emits the gate-pass marker. The boot gates under test need no live
# peers; with no seeds the boot falls through to genesis-forward
# immediately, keeping the gate fast and independent of fleet health.
"$BIN" --home "$home_dir" genesis resolve "${resolve_args[@]}" --no-write-peers \
  || fail "'protocore genesis resolve' failed — canonical genesis unavailable or hash mismatch"

# Fetch the canonical milestone config when the registry entry pins one, so
# the smoke boot matches the fleet posture (milestones are how activation
# heights + lifecycle parameters roll; the runtime parses the file at boot).
registry_base="${SMOKE_REGISTRY_URL:-https://raw.githubusercontent.com/monolythium/chain-registry/master/chains}"
registry_entry="$workdir/registry-entry.toml"
if curl -fsSL --max-time 30 "$registry_base/$REGISTRY_NETWORK.toml" -o "$registry_entry"; then
  milestones_url="$(sed -n 's/^milestones_url[[:space:]]*=[[:space:]]*"\(.*\)"/\1/p' "$registry_entry" | head -n1)"
  milestones_sha="$(sed -n 's/^milestones_sha256[[:space:]]*=[[:space:]]*"\(.*\)"/\1/p' "$registry_entry" | head -n1)"
  if [[ -n "$milestones_url" ]]; then
    curl -fsSL --max-time 30 "$milestones_url" -o "$home_dir/milestones.toml" \
      || fail "registry pins milestones_url but the fetch failed: $milestones_url"
    if [[ -n "$milestones_sha" ]]; then
      got_sha="$(sha256sum "$home_dir/milestones.toml" | cut -d' ' -f1)"
      [[ "$got_sha" == "$milestones_sha" ]] \
        || fail "milestones sha256 $got_sha != registry pin $milestones_sha"
    fi
    # `init testnet` writes a [consensus] section; add the milestones pin.
    sed -i "/^\[consensus\]/a milestones_path = \"$home_dir/milestones.toml\"" "$home_dir/config.toml"
    echo "OK: canonical milestones staged (sha256 ${milestones_sha:-unpinned})"
  else
    echo "note: registry entry pins no milestones_url — booting without milestones"
  fi
else
  echo "note: could not re-fetch the registry entry for the milestones pin — booting without milestones"
fi

# Point the indexer at the smoke Postgres. `init testnet` scaffolds
# backend = "postgres" with an empty DSN; an empty DSN is itself an
# AUD-0032 boot refusal, so this fill-in is what arms the durable path.
sed -i "s|^postgres_url = \"\"|postgres_url = \"$POSTGRES_URL\"|" "$home_dir/config.toml"
grep -q "^postgres_url = \"$POSTGRES_URL\"" "$home_dir/config.toml" \
  || fail "failed to inject SMOKE_POSTGRES_URL into config.toml"

echo "-- booting node (probe window ${BOOT_PROBE_SECS}s) --"
"$BIN" --home "$home_dir" start --node-mode full >"$boot_log" 2>&1 &
node_pid=$!

# The runtime logs this line from the postgres indexer spawn, which runs
# strictly AFTER the boot-gate walk in Node::start — seeing it proves the
# AUD-0079 zkML gate, R3-H12/H16, AUD-0027/0080 and the AUD-0032 durable-
# backend requirement all passed AND the postgres path (feature + connect +
# migrations) actually works in this binary.
gate_marker="indexer: postgres backend connected, migrations applied"
# Typed fail-fast signatures for a clearer failure message.
fail_signature='AUD-0079|AUD-0032|ZkMlPreActivationGate|Sp1VerifierFeatureMissing|boot failed'

marker_seen=0
for _ in $(seq 1 "$BOOT_PROBE_SECS"); do
  if ! kill -0 "$node_pid" 2>/dev/null; then
    wait "$node_pid" || true
    echo "---- boot log (tail) ----" >&2
    tail -n 60 "$boot_log" >&2 || true
    if grep -Eq "$fail_signature" "$boot_log"; then
      fail "node exited during boot on a fail-fast gate: $(grep -Eo "$fail_signature" "$boot_log" | sort -u | tr '\n' ' ')"
    fi
    fail "node exited during boot before clearing the boot gates"
  fi
  if grep -qF "$gate_marker" "$boot_log"; then
    marker_seen=1
    break
  fi
  sleep 1
done

if [[ "$marker_seen" != 1 ]]; then
  echo "---- boot log (tail) ----" >&2
  tail -n 60 "$boot_log" >&2 || true
  fail "gate-pass marker not seen within ${BOOT_PROBE_SECS}s: '$gate_marker'"
fi
echo "OK: boot-gate walk cleared, postgres indexer up"

# Hold window: a gate that fires just after indexer init (or any immediate
# post-boot fail-fast) still fails the release.
sleep "$HOLD_SECS"
if ! kill -0 "$node_pid" 2>/dev/null; then
  wait "$node_pid" || true
  echo "---- boot log (tail) ----" >&2
  tail -n 60 "$boot_log" >&2 || true
  fail "node died within ${HOLD_SECS}s of clearing the boot gates"
fi
if grep -Eq "$fail_signature" "$boot_log"; then
  echo "---- boot log (tail) ----" >&2
  tail -n 60 "$boot_log" >&2 || true
  fail "boot log contains a fail-fast signature: $(grep -Eo "$fail_signature" "$boot_log" | sort -u | tr '\n' ' ')"
fi

echo "PASS: artifact booted cleanly past the release boot gates (features: $features, version: $version)"
