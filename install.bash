#!/usr/bin/env bash

set -eu

if command -v tput &>/dev/null; then
  red="$(tput setaf 1 2>/dev/null || :)"
  yellow="$(tput setaf 3 2>/dev/null || :)"
  reset="$(tput sgr0 2>/dev/null || :)"
else
  red=""
  yellow=""
  reset=""
fi
readonly red yellow
readonly reset

die() {
  printf "%s%sFATAL: %s%s%s\n" "${reset}" "${red}" "${yellow}" "$1" "${reset}" >&2
  exit 1
}

# shellcheck disable=SC2268
if [ "x${BASH_VERSINFO:-}" = "x" ]; then
  die "Bash is required."
fi

# ---------->8------- CUT HERE ------8<-----------
# Everything above this line must work in POSIX shell.

set -o pipefail

if ((${BASH_VERSINFO:-0} < 3)); then
  die "Bash 3.0 or later is required."
fi

# System (OS)
os="$(uname -s)"
readonly os

# Processor (architecture)
arch="$(uname -m)"
readonly arch

# Ruby version
readonly ruby_version="3.3.2"

# Filenames and SHA256 checksums.
case "${os}/${arch}" in
Darwin/x86_64)
  ruby_filename="portable-ruby-${ruby_version}.el_capitan.bottle.tar.gz"
  ruby_sha="5c86a23e0e3caee1a4cfd958ed7d50a38e752ebaf2e7c5717e5c8eabaa6e9f12"
  ;;
Darwin/arm64)
  ruby_filename="portable-ruby-${ruby_version}.arm64_big_sur.bottle.tar.gz"
  ruby_sha="bbb73a9d86fa37128c54c74b020096a646c46c525fd5eb0c4a2467551fb2d377"
  ;;
Linux/x86_64)
  ruby_filename="portable-ruby-${ruby_version}.x86_64_linux.bottle.tar.gz"
  ruby_sha="dd3cffcc524de404e87bef92d89f3694a9ef13f2586a6dce4807456f1b30c7b0"

  ;;
*)
  printf "Unsupported platform: %s\n" "${os}/${arch}" >&2
  exit 1
  ;;
esac

readonly ruby_urls=(
  "https://ghcr.io/v2/homebrew/portable-ruby/portable-ruby/blobs/sha256:${ruby_sha}"
  "https://github.com/Homebrew/homebrew-portable-ruby/releases/download/${ruby_version}/${ruby_filename}"
)

# Follow the XDG Base Directory Specification
# https://specifications.freedesktop.org/basedir-spec/basedir-spec-latest.html
readonly data_dir="${XDG_DATA_HOME:-${HOME}/.local/share}/keybelt"
readonly runtime_dir="${XDG_RUNTIME_DIR:-${TMPDIR:-/tmp}}/keybelt"
readonly config_dir="${XDG_CONFIG_HOME:-${HOME}/.config}/keybelt"
readonly ruby_parent_dir="${data_dir}/portable-ruby"
readonly ruby_dir="${ruby_parent_dir}/${ruby_version}"
readonly temp_path="${runtime_dir}/${ruby_filename}.incomplete"
readonly ruby_tarball="${ruby_parent_dir}/${ruby_filename}"

# Returns true if the command $1 exists.
has() {
  command -v "$1" &>/dev/null
}

# Returns true if file matches the 256 check sum.
validate-sha() {
  local file="$1"
  local expected="$2"
  local actual

  if ! [[ -f ${file} ]]; then
    return 1
  fi

  if has shasum; then
    actual="$(shasum -a 256 "${file}" | awk '{print $1}' || true)"
  elif has sha256sum; then
    actual="$(sha256sum "${file}" | awk '{print $1}' || true)"
  else
    echo "Could not find a valid SHA-256 command" >&2
    exit 1
  fi

  if [[ ${actual} != "${expected}" ]]; then
    return 1
  fi
}

# Downloads a URL to file and verifies it has the expected_sha.
#
# Exit codes above 1 match the exit codes from curl's --fail mode.
download() {
  local -r url="$1"
  local -r file="$2"
  local -r expected_sha="$3"
  local -i ec=0

  local -r curl_args=(
    --disable
    --fail
    --silent
    --remote-time
    --location
    --output "${file}"
    --url "${url}"
  )

  curl "${curl_args[@]}" || ec=$?
  if ((ec)); then
    return "${ec}"
  fi

  if ! validate-sha "${file}" "${expected_sha}"; then
    rm -f "${file}"
    return 1
  fi
}

verify-requirements() {
  {
    local missing=0

    if ! has curl; then
      printf "The 'curl' command is required.\n"
      ((missing++))
    fi

    if ! has shasum && ! has sha256sum; then
      printf "The 'shasum' or 'sha256sum' command is required.\n"
      ((missing++))
    fi
  } >&2

  if ! has tar; then
    printf "The 'tar' command is required.\n"
    ((missing++))
  fi

  if ! has gzip; then
    printf "The 'gzip' command is required.\n"
    ((missing++))
  fi

  if ! has awk; then
    printf "The 'awk' command is required.\n"
    ((missing++))
  fi

  if ((missing)); then
    local noun="requirement"
    ((missing > 1)) && noun="${noun}s"
    die "Please install the missing ${noun} and try again."
  fi
}

verify-requirements

# Cleanup on exit
trap_script=$(printf 'rm -f %q\n' "${temp_path}")
readonly trap_script
# shellcheck disable=SC2064
trap "${trap_script}" EXIT

# Ensure the tmp directory is there.
mkdir -p "${runtime_dir}" "${ruby_parent_dir}"

# Skip downloading if it is already here.
if ! validate-sha "${ruby_tarball}" "${ruby_sha}"; then
  info "Downloading Portable Ruby."

  # Try several URLs
  for url in "${ruby_urls[@]}"; do
    if download "${url}" "${temp_path}" "${ruby_sha}"; then
      break
    fi
  done

  # Abort if file is missing.
  if ! [[ -f ${temp_path} ]]; then
    die "Could not download the Portable Ruby." >&2
  fi

  # Save off the tarball.
  mv -f "${temp_path}" "${ruby_tarball}"
fi

# Remove old installation.
rm -rf "${ruby_dir}"
mkdir -p "${ruby_dir}"

tar \
  --extract \
  --strip-components=2 \
  --file "${ruby_tarball}" \
  --directory "${ruby_dir}"

# Link 'current' to the version directory.
ln -nsf \
  "${ruby_dir}" \
  "${ruby_parent_dir}/current"

printf "Portable Ruby %s is now available at %s\n" \
  "${ruby_version}" \
  "${ruby_parent_dir}/current/bin/ruby"

# EOF
