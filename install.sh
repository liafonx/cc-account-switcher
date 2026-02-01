#!/usr/bin/env bash

# Multi-Account Switcher for Claude Code - Installation Script
# This script installs cc-account-switcher with automatic dependency checking

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
INSTALL_DIR="${INSTALL_DIR:-$HOME/.local/bin}"
REPO_URL="https://raw.githubusercontent.com/liafonx/cc-account-switcher/main"
SCRIPT_NAME="ccswitch.sh"
WRAPPER_NAME="ccswitch"

# Print colored message
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Detect platform
detect_platform() {
    case "$(uname -s)" in
        Darwin) echo "macos" ;;
        Linux) 
            if [[ -n "${WSL_DISTRO_NAME:-}" ]]; then
                echo "wsl"
            else
                echo "linux"
            fi
            ;;
        CYGWIN*|MINGW*|MSYS*) echo "windows" ;;
        *) echo "unknown" ;;
    esac
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check Bash version
check_bash_version() {
    local version
    version=$(bash --version | head -n1 | grep -oE '[0-9]+\.[0-9]+' | head -n1)
    
    if ! awk -v ver="$version" 'BEGIN { exit (ver >= 4.4 ? 0 : 1) }'; then
        print_error "Bash 4.4+ required (found $version)"
        return 1
    fi
    
    print_success "Bash version $version detected"
    return 0
}

# Check and install dependencies
check_dependencies() {
    local platform
    platform=$(detect_platform)
    
    print_info "Checking dependencies..."
    
    # Check for jq
    if ! command_exists jq; then
        print_warning "jq is not installed"
        
        case "$platform" in
            macos)
                if command_exists brew; then
                    print_info "Installing jq via Homebrew..."
                    brew install jq
                else
                    print_error "Homebrew not found. Please install jq manually: brew install jq"
                    print_info "Or install Homebrew from: https://brew.sh"
                    return 1
                fi
                ;;
            linux|wsl)
                if command_exists apt-get; then
                    print_info "Installing jq via apt..."
                    sudo apt-get update && sudo apt-get install -y jq
                elif command_exists yum; then
                    print_info "Installing jq via yum..."
                    sudo yum install -y jq
                elif command_exists dnf; then
                    print_info "Installing jq via dnf..."
                    sudo dnf install -y jq
                elif command_exists pacman; then
                    print_info "Installing jq via pacman..."
                    sudo pacman -S --noconfirm jq
                else
                    print_error "Could not detect package manager. Please install jq manually."
                    return 1
                fi
                ;;
            *)
                print_error "Unsupported platform. Please install jq manually."
                return 1
                ;;
        esac
    else
        print_success "jq is already installed"
    fi
    
    return 0
}

# Detect shell profile
detect_shell_profile() {
    # Check $SHELL variable first
    local shell_name
    shell_name=$(basename "${SHELL:-/bin/bash}")
    
    case "$shell_name" in
        zsh)
            if [[ -f "$HOME/.zshrc" ]]; then
                echo "$HOME/.zshrc"
            elif [[ -f "$HOME/.zprofile" ]]; then
                echo "$HOME/.zprofile"
            else
                echo "$HOME/.zshrc"  # Default
            fi
            ;;
        bash)
            if [[ -f "$HOME/.bashrc" ]]; then
                echo "$HOME/.bashrc"
            elif [[ -f "$HOME/.bash_profile" ]]; then
                echo "$HOME/.bash_profile"
            elif [[ -f "$HOME/.profile" ]]; then
                echo "$HOME/.profile"
            else
                echo "$HOME/.bashrc"  # Default
            fi
            ;;
        fish)
            echo "$HOME/.config/fish/config.fish"
            ;;
        *)
            # Try to detect from common files
            if [[ -f "$HOME/.zshrc" ]]; then
                echo "$HOME/.zshrc"
            elif [[ -f "$HOME/.bashrc" ]]; then
                echo "$HOME/.bashrc"
            else
                echo "$HOME/.profile"
            fi
            ;;
    esac
}

# Download script
download_script() {
    local install_path="$1"
    
    print_info "Downloading ccswitch.sh from GitHub..."
    
    if command_exists curl; then
        if curl -fsSL -H 'Cache-Control: no-cache, no-store' "$REPO_URL/$SCRIPT_NAME" -o "$install_path"; then
            print_success "Downloaded successfully"
            return 0
        else
            print_error "Failed to download script"
            return 1
        fi
    elif command_exists wget; then
        if wget --no-cache --no-check-certificate -q "$REPO_URL/$SCRIPT_NAME" -O "$install_path"; then
            print_success "Downloaded successfully"
            return 0
        else
            print_error "Failed to download script"
            return 1
        fi
    else
        print_error "Neither curl nor wget found. Please install one of them."
        return 1
    fi
}

# Setup wrapper function in shell profile
setup_wrapper() {
    local profile_file
    profile_file=$(detect_shell_profile)
    
    if [[ -z "$profile_file" ]]; then
        print_warning "Could not detect shell profile"
        return 1
    fi
    
    print_info "Setting up wrapper function in $profile_file..."
    
    # Check if wrapper already exists
    if grep -q "ccswitch()" "$profile_file" 2>/dev/null; then
        print_warning "Wrapper function already exists in $profile_file"
        return 0
    fi
    
    # Get the full path to the installed script
    local script_path="$INSTALL_DIR/$SCRIPT_NAME"
    
    # Add wrapper function
    cat >> "$profile_file" << EOF

# cc-account-switcher wrapper function
ccswitch() {
    "$script_path" "\$@" && [[ -f ~/.claude/.api_env ]] && source ~/.claude/.api_env
}
EOF
    
    print_success "Wrapper function added to $profile_file"
    print_info "Run 'source $profile_file' to activate in current session"
    
    return 0
}

# Main installation function
main() {
    echo ""
    echo "╔═══════════════════════════════════════════════════════╗"
    echo "║  Multi-Account Switcher for Claude Code - Installer  ║"
    echo "╚═══════════════════════════════════════════════════════╝"
    echo ""
    
    local platform
    platform=$(detect_platform)
    print_info "Platform detected: $platform"
    echo ""
    
    # Check Bash version
    if ! check_bash_version; then
        exit 1
    fi
    echo ""
    
    # Check and install dependencies
    if ! check_dependencies; then
        print_error "Dependency installation failed"
        exit 1
    fi
    echo ""
    
    # Create install directory if it doesn't exist
    if [[ ! -d "$INSTALL_DIR" ]]; then
        print_info "Creating installation directory: $INSTALL_DIR"
        mkdir -p "$INSTALL_DIR"
    fi
    
    # Add install directory to PATH if not already there
    if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
        print_warning "$INSTALL_DIR is not in your PATH"
        
        local profile_file
        profile_file=$(detect_shell_profile)
        
        if [[ -n "$profile_file" ]]; then
            print_info "Adding $INSTALL_DIR to PATH in $profile_file"
            echo "" >> "$profile_file"
            echo "# Add cc-account-switcher to PATH" >> "$profile_file"
            echo "export PATH=\"\$PATH:$INSTALL_DIR\"" >> "$profile_file"
            print_success "Added to PATH (will take effect in new shells)"
        fi
    fi
    echo ""
    
    # Download script
    local install_path="$INSTALL_DIR/$SCRIPT_NAME"
    if ! download_script "$install_path"; then
        exit 1
    fi
    echo ""
    
    # Make executable
    chmod +x "$install_path"
    print_success "Made script executable"
    echo ""
    
    # Setup wrapper function
    if setup_wrapper; then
        echo ""
        print_success "Installation complete!"
        echo ""
        echo "Next steps:"
        echo "  1. Reload your shell configuration:"
        profile_file=$(detect_shell_profile)
        echo "     source $profile_file"
        echo ""
        echo "  2. Add your first account:"
        echo "     ccswitch --add-account"
        echo ""
        echo "  3. View help for more commands:"
        echo "     ccswitch --help"
        echo ""
    else
        echo ""
        print_success "Installation complete (without wrapper)!"
        echo ""
        echo "You can run the tool directly:"
        echo "  $install_path --help"
        echo ""
        echo "Or setup the wrapper manually by adding to your shell profile:"
        echo "  ccswitch() {"
        echo "    \"$install_path\" \"\$@\" && [[ -f ~/.claude/.api_env ]] && source ~/.claude/.api_env"
        echo "  }"
        echo ""
    fi
}

# Run main if executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
