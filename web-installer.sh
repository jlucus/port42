#!/bin/bash
# Port42 Web Installer
# Served at https://port42.ai/install
#
# Usage: curl -fsSL https://port42.ai/install | bash
#
# This bootstraps the full install.sh from GitHub.
# It handles the curl-pipe-to-bash pattern by saving itself to a temp file
# and re-executing with TTY access for interactive prompts.

set -e

REPO="gordonmattey/port42"
RAW_BASE="https://raw.githubusercontent.com/${REPO}/main"

# --- TTY re-execution for curl|bash ---
# When piped, stdin is the script content, not the terminal.
# Save to a temp file and re-execute with /dev/tty attached.
if [ ! -t 0 ] || [ ! -t 1 ]; then
    TEMP_SCRIPT=$(mktemp /tmp/port42-web-installer.XXXXXX)
    cat > "$TEMP_SCRIPT"
    chmod +x "$TEMP_SCRIPT"
    if [ -e /dev/tty ]; then
        exec </dev/tty >/dev/tty 2>&1 bash "$TEMP_SCRIPT" "$@"
    else
        # No TTY available (e.g. CI) - run non-interactively
        exec bash "$TEMP_SCRIPT" --auto "$@"
    fi
fi

# Clean up temp file if we're the re-executed copy
if [[ "$0" == /tmp/port42-web-installer.* ]]; then
    trap "rm -f '$0'" EXIT
fi

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[0;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# --- Helpers ---
print_error() { echo -e "${RED}Error: $1${NC}" >&2; }
print_info()  { echo -e "${BLUE}$1${NC}"; }
print_ok()    { echo -e "${GREEN}$1${NC}"; }
print_warn()  { echo -e "${YELLOW}$1${NC}"; }

command_exists() { command -v "$1" >/dev/null 2>&1; }

# --- Prerequisites ---
if ! command_exists curl && ! command_exists wget; then
    print_error "curl or wget is required. Please install one and try again."
    exit 1
fi

# --- Parse args ---
AUTO_MODE=false
EXTRA_ARGS=()
for arg in "$@"; do
    case "$arg" in
        --auto) AUTO_MODE=true ;;
        *) EXTRA_ARGS+=("$arg") ;;
    esac
done

# --- Detect platform ---
OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case "$OS" in
    darwin)
        case "$ARCH" in
            arm64)  PLATFORM="darwin-aarch64";  PLATFORM_LABEL="macOS Apple Silicon" ;;
            x86_64) PLATFORM="darwin-x86_64";   PLATFORM_LABEL="macOS Intel" ;;
            *)      PLATFORM="darwin-${ARCH}";   PLATFORM_LABEL="macOS ($ARCH)" ;;
        esac
        ;;
    linux)
        case "$ARCH" in
            x86_64)  PLATFORM="linux-x86_64";   PLATFORM_LABEL="Linux x86_64" ;;
            aarch64) PLATFORM="linux-aarch64";   PLATFORM_LABEL="Linux ARM64" ;;
            *)       PLATFORM="linux-${ARCH}";    PLATFORM_LABEL="Linux ($ARCH)" ;;
        esac
        ;;
    *)
        print_error "Unsupported OS: $OS"
        print_info "Port42 supports macOS and Linux."
        exit 1
        ;;
esac

# --- Display banner ---
echo
echo -e "${CYAN}${BOLD}Port42 Installer${NC}"
echo -e "Detected: ${BOLD}${PLATFORM_LABEL}${NC}"
echo

# --- Check for pre-built binaries ---
VERSION=$(curl -sf "${RAW_BASE}/version.txt" 2>/dev/null || echo "0.1.1")

VERSIONED_URL="${RAW_BASE}/releases/port42-${PLATFORM}-v${VERSION}.tar.gz"
RELEASE_URL="https://github.com/${REPO}/releases/latest/download/port42-${PLATFORM}.tar.gz"

INSTALL_METHOD="source"
BINARY_URL=""

print_info "Checking for pre-built binaries (v${VERSION})..."

# Check versioned repo file first, then GitHub releases
if curl -sfI "$VERSIONED_URL" 2>/dev/null | head -n 1 | grep -q "200\|302"; then
    INSTALL_METHOD="binary"
    BINARY_URL="$VERSIONED_URL"
elif curl -sfI "$RELEASE_URL" 2>/dev/null | head -n 1 | grep -q "200\|302"; then
    INSTALL_METHOD="binary"
    BINARY_URL="$RELEASE_URL"
fi

if [ "$INSTALL_METHOD" = "binary" ]; then
    print_ok "Pre-built binaries available for ${PLATFORM} (v${VERSION})"
else
    print_warn "No pre-built binaries for ${PLATFORM}"
    # Check if build tools are available before committing to source build
    if ! command_exists go; then
        print_error "Go is required to build from source but was not found."
        print_info "Install Go (1.21+): https://go.dev/dl/"
        if ! command_exists cargo; then
            print_info "Install Rust/Cargo: https://rustup.rs/"
        fi
        exit 1
    fi
    if ! command_exists cargo; then
        print_error "Rust/Cargo is required to build from source but was not found."
        print_info "Install Rust: https://rustup.rs/"
        exit 1
    fi
    print_info "Will build from source (Go and Rust detected)"
fi

# --- Download and run the full installer ---
echo
print_info "Downloading installer..."

INSTALLER_TMP=$(mktemp /tmp/port42-install.XXXXXX)
trap "rm -f '$INSTALLER_TMP'" EXIT

if command_exists curl; then
    curl -fsSL "${RAW_BASE}/install.sh" -o "$INSTALLER_TMP"
elif command_exists wget; then
    wget -q "${RAW_BASE}/install.sh" -O "$INSTALLER_TMP"
fi

chmod +x "$INSTALLER_TMP"

# Build the argument list for the full installer
INSTALLER_ARGS=()
if [ "$AUTO_MODE" = true ]; then
    INSTALLER_ARGS+=("--auto")
fi
if [ "$INSTALL_METHOD" = "source" ]; then
    INSTALLER_ARGS+=("--build")
fi
INSTALLER_ARGS+=("${EXTRA_ARGS[@]}")

echo
exec bash "$INSTALLER_TMP" "${INSTALLER_ARGS[@]}"
