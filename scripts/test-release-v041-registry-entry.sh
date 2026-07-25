#!/usr/bin/env bash

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
verifier="$repo_root/scripts/verify-release-v041-registry-entry.sh"
test_root="$(mktemp -d)"
trap 'rm -rf "$test_root"' EXIT
entry="$test_root/testnet-69420.toml"

write_valid_entry() {
  printf '%s\n' \
    'chain_id = 69420' \
    'genesis_hash = "0x8dfc309dfe8e35b4ca036631c7dc25b29e618ac8a9694e0e2bbe23d0f98ab1fe"' \
    'genesis_sha256 = "0a02cabfb7d84cea3e77dcac76990ce3ceda233c7ba0d6f067d2b5b6e53dbb8a"' \
    'milestones_sha256 = "7739c3d702b72586dd9880bafedb3967393fab679e4d2e3268d038bcd7c452e7"' \
    'network_registry_sha256 = "ef296a44b8ea83626b9bfcbfff4df6b47049ed0cd910d07defc7dfa2ef7853d4"' \
    'binary_sha = "f052832c62ad5640fa7a419018bba4b120a18587"' \
    'binary_release_sha256 = "477704b170b620e9b52255b1dc26dddfcadb8664052867c1750ac40e3764851b"' \
    'release_tag = "v0.4.1-testnet"' \
    >"$entry"
}

expect_rejection() {
  local case_name="$1"
  if bash "$verifier" "$entry" >/dev/null 2>&1; then
    printf 'test-release-v041-registry-entry: FAIL: accepted %s\n' "$case_name" >&2
    exit 1
  fi
}

write_valid_entry
bash "$verifier" "$entry" >/dev/null

write_valid_entry
sed -i '/^network_registry_sha256[[:space:]]*=/d' "$entry"
expect_rejection "missing network_registry_sha256"

write_valid_entry
sed -i \
  's/ef296a44b8ea83626b9bfcbfff4df6b47049ed0cd910d07defc7dfa2ef7853d4/ff296a44b8ea83626b9bfcbfff4df6b47049ed0cd910d07defc7dfa2ef7853d4/' \
  "$entry"
expect_rejection "mismatched network_registry_sha256"

write_valid_entry
printf '%s\n' \
  'network_registry_sha256 = "ef296a44b8ea83626b9bfcbfff4df6b47049ed0cd910d07defc7dfa2ef7853d4"' \
  >>"$entry"
expect_rejection "duplicate network_registry_sha256"

write_valid_entry
printf '%s\n' \
  'release_tarball_sha256 = "5d03e6fb7110613b28a18cda013bd16731e5ddb02b0307fea205eacbc97f311e"' \
  >>"$entry"
expect_rejection "premature release_tarball_sha256"

printf 'test-release-v041-registry-entry: PASS\n'
