#!/usr/bin/env bash
# One-off, byte-preserving stage gate for the Posture-C R5 testnet cut.
#
# This script intentionally cannot build protocore. It accepts the already
# frozen executable, verifies its complete embedded identity, copies those
# exact bytes into the release staging area, and creates a deterministic
# distribution archive. It is release-specific by design; do not generalise it
# or change these constants for a later release.
#
# Usage:
#   scripts/release-v041-prebuilt-stage.sh BINARY OUTPUT_ROOT
#
# OUTPUT_ROOT receives:
#   work/protocore
#   verify-extract.XXXXXX/protocore
#   out/protocore-v0.4.1-testnet-x86_64-linux.tar.gz
#   out/protocore-v0.4.1-testnet-x86_64-linux.tar.gz.sha256
#   out/protocore-v0.4.1-testnet-x86_64-linux.binary.sha256
#   out/protocore-v0.4.1-testnet-x86_64-linux.release-info.json
#
# When GITHUB_OUTPUT is set, the paths and verified digests are exported as
# step outputs for the manual draft-only workflow.

set -euo pipefail

readonly RELEASE_TAG="v0.4.1-testnet"
readonly PLATFORM="x86_64-linux"
readonly ASSET="protocore-${RELEASE_TAG}-${PLATFORM}.tar.gz"
readonly EXPECTED_BINARY_SHA256="477704b170b620e9b52255b1dc26dddfcadb8664052867c1750ac40e3764851b"
readonly EXPECTED_TARBALL_SHA256="5d03e6fb7110613b28a18cda013bd16731e5ddb02b0307fea205eacbc97f311e"
readonly EXPECTED_BINARY_SIZE="41707840"
readonly EXPECTED_VERSION="0.4.0"
readonly EXPECTED_GIT_COMMIT="f052832c62ad5640fa7a419018bba4b120a18587"
readonly EXPECTED_BUILD_TIMESTAMP_UTC="1784993386"
readonly EXPECTED_FEATURES="default,indexer-postgres,mdbx,mesh,sp1-verifier"
readonly EXPECTED_PROFILE="release"
readonly EXPECTED_TARGET="x86_64-unknown-linux-gnu"
readonly EXPECTED_RUSTC="rustc 1.93.0 (254b59607 2026-01-19)"
readonly EXPECTED_CLIENT_VERSION="protocore/v2/v0.4.0-testnet-53-gf052832c+f052832c62ad"
readonly SOURCE_DATE_EPOCH="${EXPECTED_BUILD_TIMESTAMP_UTC}"

fail() {
  printf 'release-v041-prebuilt-stage: FATAL: %s\n' "$*" >&2
  exit 1
}

require_tool() {
  command -v "$1" >/dev/null 2>&1 || fail "required tool is unavailable: $1"
}

for tool in cmp gzip jq sha256sum stat strings tar; do
  require_tool "$tool"
done

binary="${1:-}"
output_root="${2:-}"
[[ -n "$binary" && -n "$output_root" ]] \
  || fail "usage: $0 BINARY OUTPUT_ROOT"
[[ -f "$binary" && -x "$binary" ]] \
  || fail "input is not an executable regular file: $binary"

binary="$(readlink -f "$binary")"
mkdir -p "$output_root"
output_root="$(readlink -f "$output_root")"
work_dir="$output_root/work"
out_dir="$output_root/out"
staged_binary="$work_dir/protocore"
asset_path="$out_dir/$ASSET"
tarball_digest_path="${asset_path}.sha256"
binary_digest_path="$out_dir/protocore-${RELEASE_TAG}-${PLATFORM}.binary.sha256"
release_info_path="$out_dir/protocore-${RELEASE_TAG}-${PLATFORM}.release-info.json"

[[ "$binary" != "$staged_binary" ]] \
  || fail "input binary must be outside the staging destination"

raw_sha="$(sha256sum "$binary" | awk '{print $1}')"
[[ "$raw_sha" == "$EXPECTED_BINARY_SHA256" ]] \
  || fail "input sha256 $raw_sha != frozen R5 sha256 $EXPECTED_BINARY_SHA256"
raw_size="$(stat -c '%s' "$binary")"
[[ "$raw_size" == "$EXPECTED_BINARY_SIZE" ]] \
  || fail "input size $raw_size != frozen R5 size $EXPECTED_BINARY_SIZE"

info_json="$("$binary" --output json release info)" \
  || fail "frozen executable did not provide release info"
printf '%s\n' "$info_json" | jq -e \
  --arg version "$EXPECTED_VERSION" \
  --arg commit "$EXPECTED_GIT_COMMIT" \
  --argjson timestamp "$EXPECTED_BUILD_TIMESTAMP_UTC" \
  --arg features "$EXPECTED_FEATURES" \
  --arg profile "$EXPECTED_PROFILE" \
  --arg target "$EXPECTED_TARGET" \
  --arg rustc "$EXPECTED_RUSTC" \
  '
    .binary == "protocore" and
    .version == $version and
    .git_commit == $commit and
    .git_dirty == false and
    .build_timestamp_utc == $timestamp and
    .features == $features and
    .profile == $profile and
    .target == $target and
    .rustc == $rustc
  ' >/dev/null \
  || fail "release-info identity does not match the frozen R5 manifest"

[[ "$("$binary" --version)" == "protocore $EXPECTED_VERSION" ]] \
  || fail "protocore --version does not report $EXPECTED_VERSION"

# The frozen binary predates its distribution tag. Pin its actual client
# version so nobody can silently substitute a rebuilt/tag-relabelled binary.
strings_tmp="$(mktemp)"
trap 'rm -f "$strings_tmp"' EXIT
strings -a "$binary" >"$strings_tmp"
grep -Fq "$EXPECTED_CLIENT_VERSION" "$strings_tmp" \
  || fail "expected frozen web3_clientVersion string is absent"

mkdir -p "$work_dir" "$out_dir"
verify_dir="$(mktemp -d "$output_root/verify-extract.XXXXXX")"

# chmod changes metadata only; the content digest is checked again immediately.
cp "$binary" "$staged_binary"
chmod 0755 "$staged_binary"
staged_sha="$(sha256sum "$staged_binary" | awk '{print $1}')"
[[ "$staged_sha" == "$EXPECTED_BINARY_SHA256" ]] \
  || fail "staged executable drifted from the frozen bytes"
cmp -s "$binary" "$staged_binary" \
  || fail "staged executable is not byte-identical to the input"

printf '%s\n' "$info_json" | jq -S . >"$release_info_path"
printf '%s  protocore\n' "$EXPECTED_BINARY_SHA256" >"$binary_digest_path"

# Reproducible archive: stable ustar headers, mode, owner/group, timestamp,
# member order, and gzip header. Re-running this step over the same bytes
# produces the same tarball digest.
tar \
  --format=ustar \
  --sort=name \
  --mtime="@${SOURCE_DATE_EPOCH}" \
  --owner=0 \
  --group=0 \
  --numeric-owner \
  --mode='u=rwx,go=rx' \
  -C "$work_dir" \
  -cf - \
  protocore \
  | gzip -n -9 >"$asset_path"

members="$(gzip -dc "$asset_path" | tar -tf -)"
[[ "$members" == "protocore" ]] \
  || fail "archive member set is not exactly 'protocore': $members"
gzip -dc "$asset_path" | tar --no-same-owner -xf - -C "$verify_dir"
[[ -f "$verify_dir/protocore" && ! -L "$verify_dir/protocore" ]] \
  || fail "archive did not extract one regular protocore executable"
[[ "$(stat -c '%a' "$verify_dir/protocore")" == "755" ]] \
  || fail "extracted executable mode is not 0755"
extracted_sha="$(sha256sum "$verify_dir/protocore" | awk '{print $1}')"
[[ "$extracted_sha" == "$EXPECTED_BINARY_SHA256" ]] \
  || fail "extracted executable sha256 $extracted_sha != $EXPECTED_BINARY_SHA256"
cmp -s "$staged_binary" "$verify_dir/protocore" \
  || fail "archive round-trip changed executable bytes"

tarball_sha="$(sha256sum "$asset_path" | awk '{print $1}')"
[[ "$tarball_sha" == "$EXPECTED_TARBALL_SHA256" ]] \
  || fail "deterministic tarball sha256 $tarball_sha != $EXPECTED_TARBALL_SHA256"
printf '%s  %s\n' "$tarball_sha" "$ASSET" >"$tarball_digest_path"

if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
  {
    printf 'asset=%s\n' "$ASSET"
    printf 'asset_path=%s\n' "$asset_path"
    printf 'binary_path=%s\n' "$staged_binary"
    printf 'binary_sha256=%s\n' "$EXPECTED_BINARY_SHA256"
    printf 'binary_digest_path=%s\n' "$binary_digest_path"
    printf 'release_info_path=%s\n' "$release_info_path"
    printf 'tarball_sha256=%s\n' "$tarball_sha"
    printf 'tarball_digest_path=%s\n' "$tarball_digest_path"
  } >>"$GITHUB_OUTPUT"
fi

printf 'release-v041-prebuilt-stage: PASS\n'
printf '  binary sha256:  %s\n' "$EXPECTED_BINARY_SHA256"
printf '  tarball sha256: %s\n' "$tarball_sha"
printf '  asset:           %s\n' "$asset_path"
