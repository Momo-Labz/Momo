#!/usr/bin/env bash
# Idempotent Cloud Agent (Linux) setup for the MOMO repository.
#
# MOMO and MOMO RELAY are macOS/iOS Xcode targets and can only be built with
# Xcode on macOS. On a Linux Cloud Agent this script prepares the portable
# pieces that DO run here: the open-source Swift toolchain (for compiling and
# exercising the shared relay contract in Shared/RelayContract.swift) and the
# Python fixture tooling under Scripts/.
set -euo pipefail

SWIFT_VERSION="6.3"
SWIFT_PLATFORM="ubuntu24.04"
SWIFT_BUILD="swift-${SWIFT_VERSION}-RELEASE"
SWIFT_DIR="/opt/swift"
SWIFT_HOME="${SWIFT_DIR}/${SWIFT_BUILD}-${SWIFT_PLATFORM}"

log() { printf '\n==> %s\n' "$*"; }

ensure_apt_deps() {
  # Required to run the swift.org Linux toolchain (see swift.org/install).
  local pkgs=(binutils git gnupg2 libc6-dev libcurl4-openssl-dev libedit2 \
    libgcc-13-dev libncurses-dev libpython3-dev libsqlite3-0 libstdc++-13-dev \
    libxml2-dev libz3-dev pkg-config tzdata zip unzip zlib1g-dev)
  local missing=()
  for p in "${pkgs[@]}"; do
    dpkg -s "$p" >/dev/null 2>&1 || missing+=("$p")
  done
  if [ "${#missing[@]}" -eq 0 ]; then
    log "Swift system dependencies already present"
    return
  fi
  log "Installing Swift system dependencies: ${missing[*]}"
  sudo apt-get update -y
  sudo DEBIAN_FRONTEND=noninteractive apt-get install -y "${missing[@]}"
}

ensure_swift() {
  if [ -x "${SWIFT_HOME}/usr/bin/swift" ]; then
    log "Swift toolchain already installed at ${SWIFT_HOME}"
  else
    ensure_apt_deps
    log "Downloading ${SWIFT_BUILD} for ${SWIFT_PLATFORM}"
    local url="https://download.swift.org/swift-${SWIFT_VERSION}-release/${SWIFT_PLATFORM//./}/${SWIFT_BUILD}/${SWIFT_BUILD}-${SWIFT_PLATFORM}.tar.gz"
    local tmp
    tmp="$(mktemp -d)"
    curl -fL --retry 4 --retry-delay 4 -o "${tmp}/swift.tar.gz" "$url"
    sudo mkdir -p "${SWIFT_DIR}"
    sudo tar xzf "${tmp}/swift.tar.gz" -C "${SWIFT_DIR}"
    rm -rf "${tmp}"
  fi

  # Stable path + PATH wiring (idempotent).
  sudo ln -sfn "${SWIFT_HOME}" "${SWIFT_DIR}/current"
  echo 'export PATH=/opt/swift/current/usr/bin:$PATH' | sudo tee /etc/profile.d/swift.sh >/dev/null
  local b
  for b in swift swiftc sourcekit-lsp; do
    sudo ln -sfn "${SWIFT_DIR}/current/usr/bin/${b}" "/usr/local/bin/${b}"
  done
}

main() {
  ensure_swift
  export PATH="/opt/swift/current/usr/bin:${PATH}"
  log "Toolchain versions"
  swift --version
  python3 --version
  log "Setup complete. Verify the portable relay contract with: Scripts/verify_relay_contract.sh"
}

main "$@"
