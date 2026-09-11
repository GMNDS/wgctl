#!/usr/bin/env bash
#
# wgctl installation script
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/gmnds/wgctl/main/install.sh | bash
#   or with custom version:
#   curl -fsSL https://raw.githubusercontent.com/gmnds/wgctl/main/install.sh | VERSION=v0.1.0 bash
#

set -e

REPO="${REPO:-gmnds/wgctl}"
BIN_DIR="${BIN_DIR:-/usr/local/bin}"
BINARY_NAME="wgctl"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
BOLD='\033[1m'
NC='\033[0m'

echo -e "${BLUE}${BOLD}"
echo "    ██╗    ██╗ ██████╗  ██████╗████████╗██╗     "
echo "    ██║    ██║██╔════╝ ██╔════╝╚══██╔══╝██║     "
echo "    ██║ █╗ ██║██║  ███╗██║        ██║   ██║     "
echo "    ██║███╗██║██║   ██║██║        ██║   ██║     "
echo "    ╚███╔███╔╝╚██████╔╝╚██████╗   ██║   ███████╗"
echo "     ╚══╝╚══╝  ╚═════╝  ╚═════╝   ╚═╝   ╚══════╝"
echo -e "${NC}"
echo -e "${BOLD}Friendly WireGuard Management CLI Installer${NC}\n"

# 1. Detect OS
OS_RAW="$(uname -s | tr '[:upper:]' '[:lower:]')"
case "${OS_RAW}" in
  linux*)  OS="linux" ;;
  darwin*) OS="darwin" ;;
  *)
    echo -e "${RED}Error: Unsupported operating system '${OS_RAW}'.${NC}"
    echo "wgctl supports Linux and macOS. For Windows, please download wgctl.exe directly from GitHub Releases."
    exit 1
    ;;
esac

# 2. Detect Architecture
ARCH_RAW="$(uname -m)"
case "${ARCH_RAW}" in
  x86_64|amd64)   ARCH="amd64" ;;
  aarch64|arm64)  ARCH="arm64" ;;
  armv7*|armhf)   ARCH="armv7" ;;
  *)
    echo -e "${RED}Error: Unsupported architecture '${ARCH_RAW}'.${NC}"
    exit 1
    ;;
esac

ASSET_NAME="${BINARY_NAME}-${OS}-${ARCH}"

# 3. Resolve version
if [ -z "${VERSION}" ] || [ "${VERSION}" = "latest" ]; then
  echo -e "Finding latest release for ${REPO}..."
  LATEST_URL="https://api.github.com/repos/${REPO}/releases/latest"
  if command -v curl >/dev/null 2>&1; then
    VERSION=$(curl -sL "${LATEST_URL}" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
  elif command -v wget >/dev/null 2>&1; then
    VERSION=$(wget -qO- "${LATEST_URL}" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
  fi

  if [ -z "${VERSION}" ]; then
    VERSION="v0.1.0"
  fi
fi

DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${VERSION}/${ASSET_NAME}"

echo -e "Platform detected: ${GREEN}${OS}/${ARCH}${NC}"
echo -e "Target version:    ${GREEN}${VERSION}${NC}"
echo -e "Downloading:       ${BLUE}${DOWNLOAD_URL}${NC}"

TMP_DIR="$(mktemp -d)"
TMP_FILE="${TMP_DIR}/${BINARY_NAME}"

cleanup() {
  rm -rf "${TMP_DIR}"
}
trap cleanup EXIT

# 4. Download binary
if command -v curl >/dev/null 2>&1; then
  curl -fsSL -o "${TMP_FILE}" "${DOWNLOAD_URL}" || {
    echo -e "${RED}Download failed.${NC} Please check your connection or tag name: ${VERSION}"
    exit 1
  }
elif command -v wget >/dev/null 2>&1; then
  wget -qO "${TMP_FILE}" "${DOWNLOAD_URL}" || {
    echo -e "${RED}Download failed.${NC} Please check your connection or tag name: ${VERSION}"
    exit 1
  }
else
  echo -e "${RED}Error: neither curl nor wget found. Please install curl or wget.${NC}"
  exit 1
fi

chmod +x "${TMP_FILE}"

# 5. Install to BIN_DIR
mkdir -p "${BIN_DIR}" 2>/dev/null || sudo mkdir -p "${BIN_DIR}"
INSTALL_CMD="cp ${TMP_FILE} ${BIN_DIR}/${BINARY_NAME}"
if [ -w "${BIN_DIR}" ]; then
  ${INSTALL_CMD}
else
  echo -e "${YELLOW}Root permissions required to install to ${BIN_DIR}.${NC}"
  sudo ${INSTALL_CMD}
fi

echo -e "\n${GREEN}${BOLD}✓ wgctl successfully installed to ${BIN_DIR}/${BINARY_NAME}!${NC}\n"

# Verify execution
if command -v "${BINARY_NAME}" >/dev/null 2>&1; then
  "${BINARY_NAME}" --version
fi

# 6. Check WireGuard tools
if ! command -v wg >/dev/null 2>&1; then
  echo -e "\n${YELLOW}${BOLD}Note:${NC} wireguard-tools ('wg') was not detected in PATH."
  echo "You can install it manually or simply run '${BOLD}wgctl init${NC}' which will detect your OS and install it automatically!"
fi

echo -e "\nRun ${BOLD}wgctl --help${NC} or ${BOLD}wgctl status${NC} to get started!"
