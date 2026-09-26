#!/bin/bash
# install.sh (macOS / Linux Automated Installer for Coursera DL)
# Repository: https://github.com/courseradl/coursera-dl-gui

set -e

# --- Styles and Formatting ---
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

GREEN='\033[1;32m'
YELLOW='\033[1;33m'
RED='\033[1;31m'
CYAN='\033[1;36m'
BLUE='\033[1;34m'

GITHUB_REPO="courseradl/coursera-dl-gui"
RELEASES_API="https://api.github.com/repos/${GITHUB_REPO}/releases/latest"

# --- UI Helpers ---
print_banner() {
    echo -e "${CYAN}${BOLD}"
    cat << "EOF"
  ____                                       ____  _     
 / ___|___  _   _ _ __ ___  ___ _ __ __ _   |  _ \| |    
| |   / _ \| | | | '__/ __|/ _ \ '__/ _` |  | | | | |    
| |__| (_) | |_| | |  \__ \  __/ | | (_| |  | |_| | |___ 
 \____\___/ \__,_|_|  |___/\___|_|  \__,_|  |____/|_____|
EOF
    echo -e "${NC}${DIM}  High-performance desktop application for personal offline course backups${NC}\n"
}

step() {
    echo -e "\n${BLUE}==>${NC} ${BOLD}$1${NC}"
}
ok() {
    echo -e " ${GREEN}✔${NC}  $1"
}
info() {
    echo -e " ${YELLOW}➜${NC}  $1"
}
die() {
    echo -e "\n ${RED}✖  ERROR:${NC} $1\n"
    exit 1
}

print_banner

# --- Phase 1: Detect OS & Architecture ---
step "Identifying system"
OS_NAME=$(uname -s)
if [ "$OS_NAME" = "Darwin" ]; then
    OS="mac"
    FORMAT="dmg"
    DISPLAY_OS="macOS (Darwin)"
elif [ "$OS_NAME" = "Linux" ]; then
    OS="linux"
    DISPLAY_OS="Linux"
    if command -v dpkg >/dev/null 2>&1; then
        FORMAT="deb"
    elif command -v rpm >/dev/null 2>&1; then
        FORMAT="rpm"
    else
        FORMAT="appimage"
    fi
else
    die "Unsupported operating system: $OS_NAME"
fi
ok "OS detected: ${BOLD}${DISPLAY_OS}${NC}"

ARCH_RAW=$(uname -m)
if [ "$ARCH_RAW" = "x86_64" ]; then
    ARCH="x64"
elif [ "$ARCH_RAW" = "arm64" ] || [ "$ARCH_RAW" = "aarch64" ]; then
    ARCH="arm64"
else
    die "Unsupported architecture: $ARCH_RAW"
fi
ok "Architecture detected: ${BOLD}${ARCH_RAW}${NC} (${ARCH})"

# --- Phase 2: Fetch Latest Release Info ---
step "Checking for latest release"
RELEASE_JSON=$(curl -sSL -H "User-Agent: Coursera-DL-Installer" -H "Accept: application/vnd.github.v3+json" "$RELEASES_API" || echo "")

if [ -z "$RELEASE_JSON" ] || ! echo "$RELEASE_JSON" | grep -q '"assets"'; then
    die "Failed to query GitHub Releases API. Please verify your internet connection."
fi

LATEST_VERSION=$(echo "$RELEASE_JSON" | grep -oE '"tag_name":\s*"[^"]+"' | head -n1 | cut -d'"' -f4 | sed 's/^v//')
ok "Latest release tag: ${CYAN}v${LATEST_VERSION}${NC}"

# Match Asset URL
DOWNLOAD_URL=""
if [ "$OS" = "mac" ]; then
    if [ "$ARCH" = "arm64" ]; then
        DOWNLOAD_URL=$(echo "$RELEASE_JSON" | grep -oE 'https://github\.com/[^"]+\.dmg' | grep -iE 'aarch64|arm64|apple_silicon' | head -n1 || true)
    fi
    if [ -z "$DOWNLOAD_URL" ]; then
        DOWNLOAD_URL=$(echo "$RELEASE_JSON" | grep -oE 'https://github\.com/[^"]+\.dmg' | grep -iE 'x64|x86_64|intel' | head -n1 || true)
    fi
    if [ -z "$DOWNLOAD_URL" ]; then
        DOWNLOAD_URL=$(echo "$RELEASE_JSON" | grep -oE 'https://github\.com/[^"]+\.dmg' | head -n1 || true)
    fi
elif [ "$OS" = "linux" ]; then
    if [ "$FORMAT" = "deb" ]; then
        DOWNLOAD_URL=$(echo "$RELEASE_JSON" | grep -oE 'https://github\.com/[^"]+\.deb' | head -n1 || true)
    elif [ "$FORMAT" = "appimage" ]; then
        DOWNLOAD_URL=$(echo "$RELEASE_JSON" | grep -oE 'https://github\.com/[^"]+\.AppImage' | head -n1 || true)
    fi
fi

if [ -z "$DOWNLOAD_URL" ]; then
    die "Could not find a compatible release asset for ${DISPLAY_OS} (${ARCH}). Please visit: https://github.com/${GITHUB_REPO}/releases/latest"
fi

# --- Phase 3: Verify Local Installation ---
SKIP_DOWNLOAD=false
APP_PATH="/Applications/Coursera DL.app"

step "Verifying local installation"
if [ "$OS" = "mac" ]; then
    if [ ! -d "$APP_PATH" ]; then
        SEARCH_PATH=$(ls -d /Applications/Coursera*.app 2>/dev/null | head -n1 || true)
        if [ -n "$SEARCH_PATH" ]; then
            APP_PATH="$SEARCH_PATH"
        fi
    fi

    if [ -d "$APP_PATH" ]; then
        LOCAL_VERSION=$(defaults read "$APP_PATH/Contents/Info" CFBundleShortVersionString 2>/dev/null || echo "0")
    else
        LOCAL_VERSION="0"
    fi
elif [ "$OS" = "linux" ]; then
    if [ "$FORMAT" = "deb" ]; then
        LOCAL_VERSION=$(dpkg -s coursera-dl-gui 2>/dev/null | grep '^Version:' | awk '{print $2}' || echo "0")
    else
        LOCAL_VERSION="0"
    fi
fi

if [ "$LOCAL_VERSION" = "$LATEST_VERSION" ] && [ "$LOCAL_VERSION" != "0" ]; then
    ok "Coursera DL is already up-to-date (${CYAN}v${LATEST_VERSION}${NC})"
    SKIP_DOWNLOAD=true
elif [ "$LOCAL_VERSION" != "0" ]; then
    info "An update is available (v${LOCAL_VERSION} -> v${LATEST_VERSION})"
else
    info "Coursera DL is not installed yet"
fi

# --- Phase 4: Download and Install ---
if [ "$SKIP_DOWNLOAD" = "false" ]; then
    FILE_EXT="${FORMAT}"
    [ "$FORMAT" = "appimage" ] && FILE_EXT="AppImage"
    
    TMP_PATH="/tmp/coursera-dl-installer.${FILE_EXT}"
    step "Downloading Coursera DL"
    info "Downloading official release artifact..."
    curl -# -L -o "$TMP_PATH" "$DOWNLOAD_URL"
    ok "Download completed"

    step "Installing application"
    if [ "$OS" = "mac" ]; then
        info "Mounting disk image..."
        MOUNT_DIR=$(hdiutil attach -nobrowse -noverify -noautoopen "$TMP_PATH" | grep -o '/Volumes/.*' | head -n1 || true)
        if [ -z "$MOUNT_DIR" ]; then die "Failed to mount disk image DMG."; fi
        
        DETECTED_APP=$(ls -d "$MOUNT_DIR"/*.app 2>/dev/null | head -n1 || true)
        if [ -z "$DETECTED_APP" ]; then
            hdiutil detach "$MOUNT_DIR" -quiet || true
            die "No .app bundle discovered inside disk image."
        fi
        
        APP_NAME=$(basename "$DETECTED_APP")
        NEW_APP_PATH="/Applications/$APP_NAME"
        
        info "Installing $APP_NAME into /Applications..."
        rm -rf "$NEW_APP_PATH" 2>/dev/null || sudo rm -rf "$NEW_APP_PATH"
        cp -R "$DETECTED_APP" /Applications/ 2>/dev/null || sudo cp -R "$DETECTED_APP" /Applications/
        xattr -cr "$NEW_APP_PATH" 2>/dev/null || sudo xattr -cr "$NEW_APP_PATH" 2>/dev/null || true
        
        hdiutil detach "$MOUNT_DIR" -quiet || true
        rm -f "$TMP_PATH"
        ok "$APP_NAME successfully installed to /Applications"
    elif [ "$FORMAT" = "deb" ]; then
        info "Installing DEB package..."
        sudo dpkg -i "$TMP_PATH" || sudo apt-get install -f -y
        rm -f "$TMP_PATH"
        ok "DEB package installed successfully"
    elif [ "$FORMAT" = "appimage" ]; then
        mkdir -p "$HOME/.local/bin"
        mv "$TMP_PATH" "$HOME/.local/bin/coursera-dl"
        chmod +x "$HOME/.local/bin/coursera-dl"
        ok "AppImage installed to $HOME/.local/bin/coursera-dl"
    fi
fi

# --- Completion Summary ---
echo -e "\n${GREEN}${BOLD}🎉 Installation Complete!${NC}"
if [ "$OS" = "mac" ]; then
    echo -e "You can now launch ${BOLD}Coursera DL${NC} from Spotlight, Launchpad, or ${CYAN}/Applications${NC}.\n"
else
    echo -e "You can now launch ${BOLD}Coursera DL${NC} from your application menu or terminal.\n"
fi
