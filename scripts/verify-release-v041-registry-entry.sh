#!/usr/bin/env bash
# Fail-closed verifier for the one exact Posture-C R5 chain-registry entry.

set -euo pipefail

readonly EXPECTED_CHAIN_ID="69420"
readonly EXPECTED_GENESIS_HASH="0x8dfc309dfe8e35b4ca036631c7dc25b29e618ac8a9694e0e2bbe23d0f98ab1fe"
readonly EXPECTED_GENESIS_SHA256="0a02cabfb7d84cea3e77dcac76990ce3ceda233c7ba0d6f067d2b5b6e53dbb8a"
readonly EXPECTED_MILESTONES_SHA256="7739c3d702b72586dd9880bafedb3967393fab679e4d2e3268d038bcd7c452e7"
readonly EXPECTED_NETWORK_REGISTRY_SHA256="ef296a44b8ea83626b9bfcbfff4df6b47049ed0cd910d07defc7dfa2ef7853d4"
readonly EXPECTED_BINARY_COMMIT="f052832c62ad5640fa7a419018bba4b120a18587"
readonly EXPECTED_BINARY_SHA256="477704b170b620e9b52255b1dc26dddfcadb8664052867c1750ac40e3764851b"
readonly EXPECTED_RELEASE_TAG="v0.4.1-testnet"

fail() {
  printf 'verify-release-v041-registry-entry: FATAL: %s\n' "$*" >&2
  exit 1
}

entry="${1:-}"
[[ -n "$entry" ]] || fail "usage: $0 ENTRY"
[[ -f "$entry" && ! -L "$entry" ]] \
  || fail "entry is not a regular, non-symlink file: $entry"

require_exact_assignment() {
  local key="$1"
  local expected="$2"
  local line
  local rhs
  local assignment_count=0
  local exact_count=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    line="${line%$'\r'}"
    if [[ "$line" =~ ^[[:space:]]*${key}[[:space:]]*= ]]; then
      assignment_count=$((assignment_count + 1))
      rhs="${line#*=}"
      rhs="${rhs#"${rhs%%[![:space:]]*}"}"
      rhs="${rhs%"${rhs##*[![:space:]]}"}"
      if [[ "$rhs" == "$expected" ]]; then
        exact_count=$((exact_count + 1))
      fi
    fi
  done <"$entry"

  [[ "$assignment_count" == 1 && "$exact_count" == 1 ]] \
    || fail "$key must occur exactly once with the frozen R5 value"
}

require_exact_assignment chain_id "$EXPECTED_CHAIN_ID"
require_exact_assignment genesis_hash "\"$EXPECTED_GENESIS_HASH\""
require_exact_assignment genesis_sha256 "\"$EXPECTED_GENESIS_SHA256\""
require_exact_assignment milestones_sha256 "\"$EXPECTED_MILESTONES_SHA256\""
require_exact_assignment network_registry_sha256 "\"$EXPECTED_NETWORK_REGISTRY_SHA256\""
require_exact_assignment binary_sha "\"$EXPECTED_BINARY_COMMIT\""
require_exact_assignment binary_release_sha256 "\"$EXPECTED_BINARY_SHA256\""
require_exact_assignment release_tag "\"$EXPECTED_RELEASE_TAG\""

if grep -Eq '^[[:space:]]*release_tarball_sha256[[:space:]]*=' "$entry"; then
  fail "candidate must not declare a tarball digest before the workflow creates it"
fi

printf 'verify-release-v041-registry-entry: PASS\n'
