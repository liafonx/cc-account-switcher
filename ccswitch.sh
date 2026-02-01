#!/usr/bin/env bash

# Multi-Account Switcher for Claude Code
# Simple tool to manage and switch between multiple Claude Code accounts

set -euo pipefail

# Configuration
readonly BACKUP_DIR="$HOME/.claude-switch-backup"
readonly SEQUENCE_FILE="$BACKUP_DIR/sequence.json"
readonly API_ACCOUNTS_FILE="$BACKUP_DIR/api_accounts.json"
readonly CC_MARKER_START="# >>> cc-account-switcher >>>"
readonly CC_MARKER_END="# <<< cc-account-switcher <<<"

# Container detection
is_running_in_container() {
    # Check for Docker environment file
    if [[ -f /.dockerenv ]]; then
        return 0
    fi
    
    # Check cgroup for container indicators
    if [[ -f /proc/1/cgroup ]] && grep -q 'docker\|lxc\|containerd\|kubepods' /proc/1/cgroup 2>/dev/null; then
        return 0
    fi
    
    # Check mount info for container filesystems
    if [[ -f /proc/self/mountinfo ]] && grep -q 'docker\|overlay' /proc/self/mountinfo 2>/dev/null; then
        return 0
    fi
    
    # Check for common container environment variables
    if [[ -n "${CONTAINER:-}" ]] || [[ -n "${container:-}" ]]; then
        return 0
    fi
    
    return 1
}

# Platform detection
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
        *) echo "unknown" ;;
    esac
}

# Get Claude configuration file path with fallback
get_claude_config_path() {
    local primary_config="$HOME/.claude/.claude.json"
    local fallback_config="$HOME/.claude.json"
    
    # Check primary location first
    if [[ -f "$primary_config" ]]; then
        # Verify it has valid oauthAccount structure
        if jq -e '.oauthAccount' "$primary_config" >/dev/null 2>&1; then
            echo "$primary_config"
            return
        fi
    fi
    
    # Fallback to standard location
    echo "$fallback_config"
}

# Basic validation that JSON is valid
validate_json() {
    local file="$1"
    if ! jq . "$file" >/dev/null 2>&1; then
        echo "Error: Invalid JSON in $file"
        return 1
    fi
}

# Email validation function
validate_email() {
    local email="$1"
    # Use robust regex for email validation
    if [[ "$email" =~ ^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$ ]]; then
        return 0
    else
        return 1
    fi
}

# Account identifier resolution function
resolve_account_identifier() {
    local identifier="$1"
    if [[ "$identifier" =~ ^[0-9]+$ ]]; then
        echo "$identifier"  # It's a number
    else
        # Look up account number by email
        local account_num
        account_num=$(jq -r --arg email "$identifier" '.accounts | to_entries[] | select(.value.email == $email) | .key' "$SEQUENCE_FILE" 2>/dev/null)
        if [[ -n "$account_num" && "$account_num" != "null" ]]; then
            echo "$account_num"
        else
            echo ""
        fi
    fi
}

# Safe JSON write with validation
write_json() {
    local file="$1"
    local content="$2"
    local temp_file
    temp_file=$(mktemp "${file}.XXXXXX")
    
    echo "$content" > "$temp_file"
    if ! jq . "$temp_file" >/dev/null 2>&1; then
        rm -f "$temp_file"
        echo "Error: Generated invalid JSON"
        return 1
    fi
    
    mv "$temp_file" "$file"
    chmod 600 "$file"
}

# Check Bash version (4.4+ required)
check_bash_version() {
    local version
    version=$(bash --version | head -n1 | grep -oE '[0-9]+\.[0-9]+' | head -n1)
    if ! awk -v ver="$version" 'BEGIN { exit (ver >= 4.4 ? 0 : 1) }'; then
        echo "Error: Bash 4.4+ required (found $version)"
        exit 1
    fi
}

# Check dependencies
check_dependencies() {
    for cmd in jq; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            echo "Error: Required command '$cmd' not found"
            echo "Install with: apt install $cmd (Linux) or brew install $cmd (macOS)"
            exit 1
        fi
    done
}

# Setup backup directories
setup_directories() {
    mkdir -p "$BACKUP_DIR"/{configs,credentials}
    chmod 700 "$BACKUP_DIR"
    chmod 700 "$BACKUP_DIR"/{configs,credentials}
}

# Claude Code process detection (Node.js app)
is_claude_running() {
    ps -eo pid,comm,args | awk '$2 == "claude" || $3 == "claude" {exit 0} END {exit 1}'
}

# Wait for Claude Code to close (no timeout - user controlled)
wait_for_claude_close() {
    if ! is_claude_running; then
        return 0
    fi
    
    echo "Claude Code is running. Please close it first."
    echo "Waiting for Claude Code to close..."
    
    while is_claude_running; do
        sleep 1
    done
    
    echo "Claude Code closed. Continuing..."
}

# Get current account info from .claude.json
get_current_account() {
    if [[ ! -f "$(get_claude_config_path)" ]]; then
        echo "none"
        return
    fi
    
    if ! validate_json "$(get_claude_config_path)"; then
        echo "none"
        return
    fi
    
    local email
    email=$(jq -r '.oauthAccount.emailAddress // empty' "$(get_claude_config_path)" 2>/dev/null)
    echo "${email:-none}"
}

# Read credentials based on platform
read_credentials() {
    local platform
    platform=$(detect_platform)
    
    case "$platform" in
        macos)
            security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null || echo ""
            ;;
        linux|wsl)
            if [[ -f "$HOME/.claude/.credentials.json" ]]; then
                cat "$HOME/.claude/.credentials.json"
            else
                echo ""
            fi
            ;;
    esac
}

# Write credentials based on platform
write_credentials() {
    local credentials="$1"
    local platform
    platform=$(detect_platform)
    
    case "$platform" in
        macos)
            security add-generic-password -U -s "Claude Code-credentials" -a "$USER" -w "$credentials" 2>/dev/null
            ;;
        linux|wsl)
            mkdir -p "$HOME/.claude"
            printf '%s' "$credentials" > "$HOME/.claude/.credentials.json"
            chmod 600 "$HOME/.claude/.credentials.json"
            ;;
    esac
}

# Read account credentials from backup
read_account_credentials() {
    local account_num="$1"
    local email="$2"
    local platform
    platform=$(detect_platform)
    
    case "$platform" in
        macos)
            security find-generic-password -s "Claude Code-Account-${account_num}-${email}" -w 2>/dev/null || echo ""
            ;;
        linux|wsl)
            local cred_file="$BACKUP_DIR/credentials/.claude-credentials-${account_num}-${email}.json"
            if [[ -f "$cred_file" ]]; then
                cat "$cred_file"
            else
                echo ""
            fi
            ;;
    esac
}

# Write account credentials to backup
write_account_credentials() {
    local account_num="$1"
    local email="$2"
    local credentials="$3"
    local platform
    platform=$(detect_platform)
    
    case "$platform" in
        macos)
            security add-generic-password -U -s "Claude Code-Account-${account_num}-${email}" -a "$USER" -w "$credentials" 2>/dev/null
            ;;
        linux|wsl)
            local cred_file="$BACKUP_DIR/credentials/.claude-credentials-${account_num}-${email}.json"
            printf '%s' "$credentials" > "$cred_file"
            chmod 600 "$cred_file"
            ;;
    esac
}

# Read account config from backup
read_account_config() {
    local account_num="$1"
    local email="$2"
    local config_file="$BACKUP_DIR/configs/.claude-config-${account_num}-${email}.json"
    
    if [[ -f "$config_file" ]]; then
        cat "$config_file"
    else
        echo ""
    fi
}

# Write account config to backup
write_account_config() {
    local account_num="$1"
    local email="$2"
    local config="$3"
    local config_file="$BACKUP_DIR/configs/.claude-config-${account_num}-${email}.json"
    
    echo "$config" > "$config_file"
    chmod 600 "$config_file"
}

# Setup API environment for Claude Code
setup_api_environment() {
    local account_num="$1"
    
    if [[ ! -f "$API_ACCOUNTS_FILE" ]]; then
        echo "Error: API accounts file not found"
        return 1
    fi
    
    local api_data
    api_data=$(jq -r --arg num "$account_num" '.accounts[$num] // empty' "$API_ACCOUNTS_FILE")
    
    if [[ -z "$api_data" ]]; then
        echo "Error: No API account data found for Account-$account_num"
        return 1
    fi
    
    local base_url auth_token
    base_url=$(echo "$api_data" | jq -r '.baseUrl')
    auth_token=$(echo "$api_data" | jq -r '.authToken')
    
    # Create/update Claude Code environment configuration
    # Note: Claude Code reads these from environment or config
    local env_file="$HOME/.claude/.api_env"
    mkdir -p "$HOME/.claude"
    
    cat > "$env_file" << EOF
export ANTHROPIC_BASE_URL="$base_url"
export ANTHROPIC_AUTH_TOKEN="$auth_token"
EOF
    chmod 600 "$env_file"
    
    # Update shell profile for persistence across terminal sessions
    update_shell_profile "$base_url" "$auth_token"
    
    echo "API environment configured. Base URL: $base_url"
}

# Clear API environment
clear_api_environment() {
    local env_file="$HOME/.claude/.api_env"
    if [[ -f "$env_file" ]]; then
        rm -f "$env_file"
    fi
    
    # Remove exports from shell profile
    remove_from_shell_profile
}

# Detect user's shell profile file
detect_shell_profile() {
    # Detect shell type
    local shell_name
    shell_name=$(basename "${SHELL:-/bin/bash}")
    
    # Check for common profile files in order of preference
    local profile_file=""
    
    case "$shell_name" in
        zsh)
            # For zsh, prefer .zshrc
            if [[ -f "$HOME/.zshrc" ]]; then
                profile_file="$HOME/.zshrc"
            elif [[ -f "$HOME/.zprofile" ]]; then
                profile_file="$HOME/.zprofile"
            else
                # Create .zshrc if it doesn't exist
                touch "$HOME/.zshrc"
                profile_file="$HOME/.zshrc"
            fi
            ;;
        bash)
            # For bash, prefer .bashrc, then .bash_profile
            if [[ -f "$HOME/.bashrc" ]]; then
                profile_file="$HOME/.bashrc"
            elif [[ -f "$HOME/.bash_profile" ]]; then
                profile_file="$HOME/.bash_profile"
            elif [[ -f "$HOME/.profile" ]]; then
                profile_file="$HOME/.profile"
            else
                # Create .bashrc if it doesn't exist
                touch "$HOME/.bashrc"
                profile_file="$HOME/.bashrc"
            fi
            ;;
        *)
            # Default to .profile for other shells
            if [[ -f "$HOME/.profile" ]]; then
                profile_file="$HOME/.profile"
            else
                touch "$HOME/.profile"
                profile_file="$HOME/.profile"
            fi
            ;;
    esac
    
    echo "$profile_file"
}

# Update shell profile with API environment variables
update_shell_profile() {
    local base_url="$1"
    local auth_token="$2"
    
    local profile_file
    profile_file=$(detect_shell_profile)
    
    if [[ -z "$profile_file" ]]; then
        echo "Warning: Could not detect shell profile file"
        return 1
    fi
    
    # Remove existing cc-account-switcher block if present
    remove_from_shell_profile
    
    # Add new exports to profile with blank line before marker for readability
    cat >> "$profile_file" << EOF

$CC_MARKER_START
# Claude Code API Configuration - managed by cc-account-switcher
export ANTHROPIC_BASE_URL="$base_url"
export ANTHROPIC_AUTH_TOKEN="$auth_token"
$CC_MARKER_END
EOF
    
    echo "Updated shell profile: $profile_file"
    echo "Changes will take effect in new terminal sessions or after running:"
    echo "  source $profile_file"
}

# Remove cc-account-switcher exports from shell profile
remove_from_shell_profile() {
    local profile_file
    profile_file=$(detect_shell_profile)
    
    if [[ -z "$profile_file" || ! -f "$profile_file" ]]; then
        return 0
    fi
    
    # Check if markers exist
    if ! grep -q "$CC_MARKER_START" "$profile_file" 2>/dev/null; then
        return 0
    fi
    
    # Create temporary file
    local temp_file
    temp_file=$(mktemp "${profile_file}.XXXXXX")
    
    # Remove lines between markers (inclusive)
    awk -v start="$CC_MARKER_START" -v end="$CC_MARKER_END" '
        $0 ~ start { skip=1; next }
        $0 ~ end { skip=0; next }
        !skip { print }
    ' "$profile_file" > "$temp_file"
    
    # Replace original file
    mv "$temp_file" "$profile_file"
}

# Initialize sequence.json if it doesn't exist
init_sequence_file() {
    if [[ ! -f "$SEQUENCE_FILE" ]]; then
        local init_content='{
  "activeAccountNumber": null,
  "lastUpdated": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
  "sequence": [],
  "accounts": {}
}'
        write_json "$SEQUENCE_FILE" "$init_content"
    fi
}

# Initialize api_accounts.json if it doesn't exist
init_api_accounts_file() {
    if [[ ! -f "$API_ACCOUNTS_FILE" ]]; then
        local init_content='{
  "lastUpdated": "'$(date -u +%Y-%m-%dT%H:%M:%SZ)'",
  "accounts": {}
}'
        write_json "$API_ACCOUNTS_FILE" "$init_content"
    fi
}

# Get next account number
get_next_account_number() {
    if [[ ! -f "$SEQUENCE_FILE" ]]; then
        echo "1"
        return
    fi
    
    local max_num
    max_num=$(jq -r '.accounts | keys | map(tonumber) | max // 0' "$SEQUENCE_FILE")
    echo $((max_num + 1))
}

# Check if account exists by email
account_exists() {
    local email="$1"
    if [[ ! -f "$SEQUENCE_FILE" ]]; then
        return 1
    fi
    
    jq -e --arg email "$email" '.accounts[] | select(.email == $email)' "$SEQUENCE_FILE" >/dev/null 2>&1
}

# Get account type (oauth or api)
get_account_type() {
    local account_num="$1"
    if [[ ! -f "$SEQUENCE_FILE" ]]; then
        echo "oauth"
        return
    fi
    
    local account_type
    account_type=$(jq -r --arg num "$account_num" '.accounts[$num].type // "oauth"' "$SEQUENCE_FILE" 2>/dev/null)
    echo "${account_type:-oauth}"
}

# Add API account from environment variables
add_api_account_from_env() {
    local base_url="${ANTHROPIC_BASE_URL:-}"
    local auth_token="${ANTHROPIC_AUTH_TOKEN:-}"
    
    # Check each variable individually for better error messages
    local missing_vars=()
    if [[ -z "$base_url" ]]; then
        missing_vars+=("ANTHROPIC_BASE_URL")
    fi
    if [[ -z "$auth_token" ]]; then
        missing_vars+=("ANTHROPIC_AUTH_TOKEN")
    fi
    
    if [[ ${#missing_vars[@]} -gt 0 ]]; then
        echo "Error: The following environment variable(s) must be set: ${missing_vars[*]}"
        exit 1
    fi
    
    setup_directories
    init_sequence_file
    init_api_accounts_file
    
    local account_name="${1:-API Account}"
    local account_num
    account_num=$(get_next_account_number)
    
    # Generate a unique identifier for this API account
    local api_identifier="api-account-${account_num}"
    
    # Store API credentials
    local updated_api_accounts
    updated_api_accounts=$(jq --arg num "$account_num" --arg url "$base_url" --arg token "$auth_token" --arg name "$account_name" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
        .accounts[$num] = {
            name: $name,
            baseUrl: $url,
            authToken: $token,
            added: $now
        } |
        .lastUpdated = $now
    ' "$API_ACCOUNTS_FILE")
    
    write_json "$API_ACCOUNTS_FILE" "$updated_api_accounts"
    
    # Update sequence.json with unique identifier
    local updated_sequence
    updated_sequence=$(jq --arg num "$account_num" --arg name "$account_name" --arg uuid "$api_identifier" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
        .accounts[$num] = {
            email: $name,
            uuid: $uuid,
            type: "api",
            added: $now
        } |
        .sequence += [$num | tonumber] |
        .lastUpdated = $now
    ' "$SEQUENCE_FILE")
    
    write_json "$SEQUENCE_FILE" "$updated_sequence"
    
    echo "Added API Account $account_num: $account_name"
    echo "  Base URL: $base_url"
}

# Add account
cmd_add_account() {
    local account_type="${1:-oauth}"
    local account_name="${2:-}"
    
    # Handle API account
    if [[ "$account_type" == "api" ]]; then
        add_api_account_from_env "$account_name"
        return
    fi
    
    # Handle OAuth account
    setup_directories
    init_sequence_file
    
    local current_email
    current_email=$(get_current_account)
    
    if [[ "$current_email" == "none" ]]; then
        echo "Error: No active Claude account found. Please log in first."
        exit 1
    fi
    
    if account_exists "$current_email"; then
        echo "Account $current_email is already managed."
        exit 0
    fi
    
    local account_num
    account_num=$(get_next_account_number)
    
    # Backup current credentials and config
    local current_creds current_config
    current_creds=$(read_credentials)
    current_config=$(cat "$(get_claude_config_path)")
    
    if [[ -z "$current_creds" ]]; then
        echo "Error: No credentials found for current account"
        exit 1
    fi
    
    # Get account UUID
    local account_uuid
    account_uuid=$(jq -r '.oauthAccount.accountUuid' "$(get_claude_config_path)")
    
    # Store backups
    write_account_credentials "$account_num" "$current_email" "$current_creds"
    write_account_config "$account_num" "$current_email" "$current_config"
    
    # Update sequence.json
    local updated_sequence
    updated_sequence=$(jq --arg num "$account_num" --arg email "$current_email" --arg uuid "$account_uuid" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
        .accounts[$num] = {
            email: $email,
            uuid: $uuid,
            type: "oauth",
            added: $now
        } |
        .sequence += [$num | tonumber] |
        .activeAccountNumber = ($num | tonumber) |
        .lastUpdated = $now
    ' "$SEQUENCE_FILE")
    
    write_json "$SEQUENCE_FILE" "$updated_sequence"
    
    echo "Added Account $account_num: $current_email"
}

# Remove account
cmd_remove_account() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: $0 --remove-account <account_number|email>"
        exit 1
    fi
    
    local identifier="$1"
    local account_num
    
    if [[ ! -f "$SEQUENCE_FILE" ]]; then
        echo "Error: No accounts are managed yet"
        exit 1
    fi
    
    # Handle email vs numeric identifier
    if [[ "$identifier" =~ ^[0-9]+$ ]]; then
        account_num="$identifier"
    else
        # Validate email format
        if ! validate_email "$identifier"; then
            echo "Error: Invalid email format: $identifier"
            exit 1
        fi
        
        # Resolve email to account number
        account_num=$(resolve_account_identifier "$identifier")
        if [[ -z "$account_num" ]]; then
            echo "Error: No account found with email: $identifier"
            exit 1
        fi
    fi
    
    local account_info
    account_info=$(jq -r --arg num "$account_num" '.accounts[$num] // empty' "$SEQUENCE_FILE")
    
    if [[ -z "$account_info" ]]; then
        echo "Error: Account-$account_num does not exist"
        exit 1
    fi
    
    local email
    email=$(echo "$account_info" | jq -r '.email')
    
    local active_account
    active_account=$(jq -r '.activeAccountNumber' "$SEQUENCE_FILE")
    
    if [[ "$active_account" == "$account_num" ]]; then
        echo "Warning: Account-$account_num ($email) is currently active"
    fi
    
    echo -n "Are you sure you want to permanently remove Account-$account_num ($email)? [y/N] "
    read -r confirm
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        echo "Cancelled"
        exit 0
    fi
    
    # Remove backup files
    local platform
    platform=$(detect_platform)
    local account_type
    account_type=$(get_account_type "$account_num")
    
    if [[ "$account_type" == "api" ]]; then
        # Remove API account data
        local updated_api_accounts
        updated_api_accounts=$(jq --arg num "$account_num" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
            del(.accounts[$num]) |
            .lastUpdated = $now
        ' "$API_ACCOUNTS_FILE")
        write_json "$API_ACCOUNTS_FILE" "$updated_api_accounts"
    else
        # Remove OAuth account data
        case "$platform" in
            macos)
                security delete-generic-password -s "Claude Code-Account-${account_num}-${email}" 2>/dev/null || true
                ;;
            linux|wsl)
                rm -f "$BACKUP_DIR/credentials/.claude-credentials-${account_num}-${email}.json"
                ;;
        esac
        rm -f "$BACKUP_DIR/configs/.claude-config-${account_num}-${email}.json"
    fi
    
    # Update sequence.json
    local updated_sequence
    updated_sequence=$(jq --arg num "$account_num" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
        del(.accounts[$num]) |
        .sequence = (.sequence | map(select(. != ($num | tonumber)))) |
        .lastUpdated = $now
    ' "$SEQUENCE_FILE")
    
    write_json "$SEQUENCE_FILE" "$updated_sequence"
    
    echo "Account-$account_num ($email) has been removed"
}

# First-run setup workflow
first_run_setup() {
    local current_email
    current_email=$(get_current_account)
    
    if [[ "$current_email" == "none" ]]; then
        echo "No active Claude account found. Please log in first."
        return 1
    fi
    
    echo -n "No managed accounts found. Add current account ($current_email) to managed list? [Y/n] "
    read -r response
    
    if [[ "$response" == "n" || "$response" == "N" ]]; then
        echo "Setup cancelled. You can run '$0 --add-account' later."
        return 1
    fi
    
    cmd_add_account
    return 0
}

# List accounts
cmd_list() {
    if [[ ! -f "$SEQUENCE_FILE" ]]; then
        echo "No accounts are managed yet."
        first_run_setup
        exit 0
    fi
    
    # Get current active account from .claude.json
    local current_email
    current_email=$(get_current_account)
    
    # Find which account number corresponds to the current email
    local active_account_num=""
    if [[ "$current_email" != "none" ]]; then
        active_account_num=$(jq -r --arg email "$current_email" '.accounts | to_entries[] | select(.value.email == $email) | .key' "$SEQUENCE_FILE" 2>/dev/null)
    fi
    
    echo "Accounts:"
    jq -r --arg active "$active_account_num" '
        .sequence[] as $num |
        .accounts["\($num)"] |
        if "\($num)" == $active then
            "  \($num): \(.email) [\(.type // "oauth")] (active)"
        else
            "  \($num): \(.email) [\(.type // "oauth")]"
        end
    ' "$SEQUENCE_FILE"
}

# Switch to next account
cmd_switch() {
    if [[ ! -f "$SEQUENCE_FILE" ]]; then
        echo "Error: No accounts are managed yet"
        exit 1
    fi
    
    local active_account sequence
    active_account=$(jq -r '.activeAccountNumber' "$SEQUENCE_FILE")
    sequence=($(jq -r '.sequence[]' "$SEQUENCE_FILE"))
    
    # If no active account, start with the first one
    if [[ -z "$active_account" || "$active_account" == "null" ]]; then
        if [[ ${#sequence[@]} -eq 0 ]]; then
            echo "Error: No accounts available to switch to"
            exit 1
        fi
        perform_switch "${sequence[0]}"
        return
    fi
    
    # Check if current active account type is OAuth and verify it matches
    local active_type
    active_type=$(get_account_type "$active_account")
    
    if [[ "$active_type" == "oauth" ]]; then
        local current_email
        current_email=$(get_current_account)
        
        if [[ "$current_email" == "none" ]]; then
            echo "Error: No active Claude account found"
            exit 1
        fi
        
        # Check if current account is managed
        if ! account_exists "$current_email"; then
            echo "Notice: Active account '$current_email' was not managed."
            cmd_add_account "oauth"
            local account_num
            account_num=$(jq -r '.activeAccountNumber' "$SEQUENCE_FILE")
            echo "It has been automatically added as Account-$account_num."
            echo "Please run './ccswitch.sh --switch' again to switch to the next account."
            exit 0
        fi
    fi
    
    # wait_for_claude_close
    
    # Find next account in sequence
    local next_account current_index=0
    for i in "${!sequence[@]}"; do
        if [[ "${sequence[i]}" == "$active_account" ]]; then
            current_index=$i
            break
        fi
    done
    
    next_account="${sequence[$(((current_index + 1) % ${#sequence[@]}))]}"
    
    perform_switch "$next_account"
}

# Switch to specific account
cmd_switch_to() {
    if [[ $# -eq 0 ]]; then
        echo "Usage: $0 --switch-to <account_number|email>"
        exit 1
    fi
    
    local identifier="$1"
    local target_account
    
    if [[ ! -f "$SEQUENCE_FILE" ]]; then
        echo "Error: No accounts are managed yet"
        exit 1
    fi
    
    # Handle email vs numeric identifier
    if [[ "$identifier" =~ ^[0-9]+$ ]]; then
        target_account="$identifier"
    else
        # Validate email format
        if ! validate_email "$identifier"; then
            echo "Error: Invalid email format: $identifier"
            exit 1
        fi
        
        # Resolve email to account number
        target_account=$(resolve_account_identifier "$identifier")
        if [[ -z "$target_account" ]]; then
            echo "Error: No account found with email: $identifier"
            exit 1
        fi
    fi
    
    local account_info
    account_info=$(jq -r --arg num "$target_account" '.accounts[$num] // empty' "$SEQUENCE_FILE")
    
    if [[ -z "$account_info" ]]; then
        echo "Error: Account-$target_account does not exist"
        exit 1
    fi
    
    # wait_for_claude_close
    perform_switch "$target_account"
}

# Perform the actual account switch
perform_switch() {
    local target_account="$1"
    
    # Get target account type
    local target_type
    target_type=$(get_account_type "$target_account")
    
    if [[ "$target_type" == "api" ]]; then
        # Switching to API account
        perform_switch_to_api "$target_account"
    else
        # Switching to OAuth account
        perform_switch_to_oauth "$target_account"
    fi
}

# Perform switch to OAuth account
perform_switch_to_oauth() {
    local target_account="$1"
    
    # Get current and target account info
    local current_account target_email current_email
    current_account=$(jq -r '.activeAccountNumber' "$SEQUENCE_FILE")
    target_email=$(jq -r --arg num "$target_account" '.accounts[$num].email' "$SEQUENCE_FILE")
    current_email=$(get_current_account)
    
    # If current account is OAuth, backup it first
    local current_type
    current_type=$(get_account_type "$current_account")
    
    if [[ "$current_type" == "oauth" && "$current_account" != "null" ]]; then
        # Step 1: Backup current account
        local current_creds current_config
        current_creds=$(read_credentials)
        current_config=$(cat "$(get_claude_config_path)")
        
        write_account_credentials "$current_account" "$current_email" "$current_creds"
        write_account_config "$current_account" "$current_email" "$current_config"
    fi
    
    # Clear API environment if switching from API account
    if [[ "$current_type" == "api" ]]; then
        clear_api_environment
    fi
    
    # Step 2: Retrieve target account
    local target_creds target_config
    target_creds=$(read_account_credentials "$target_account" "$target_email")
    target_config=$(read_account_config "$target_account" "$target_email")
    
    if [[ -z "$target_creds" || -z "$target_config" ]]; then
        echo "Error: Missing backup data for Account-$target_account"
        exit 1
    fi
    
    # Step 3: Activate target account
    write_credentials "$target_creds"
    
    # Extract oauthAccount from backup and validate
    local oauth_section
    oauth_section=$(echo "$target_config" | jq '.oauthAccount' 2>/dev/null)
    if [[ -z "$oauth_section" || "$oauth_section" == "null" ]]; then
        echo "Error: Invalid oauthAccount in backup"
        exit 1
    fi
    
    # Merge with current config and validate
    local merged_config
    merged_config=$(jq --argjson oauth "$oauth_section" '.oauthAccount = $oauth' "$(get_claude_config_path)" 2>/dev/null)
    if [[ $? -ne 0 ]]; then
        echo "Error: Failed to merge config"
        exit 1
    fi
    
    # Use existing safe write_json function
    write_json "$(get_claude_config_path)" "$merged_config"
    
    # Step 4: Update state
    local updated_sequence
    updated_sequence=$(jq --arg num "$target_account" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
        .activeAccountNumber = ($num | tonumber) |
        .lastUpdated = $now
    ' "$SEQUENCE_FILE")
    
    write_json "$SEQUENCE_FILE" "$updated_sequence"
    
    echo "Switched to Account-$target_account ($target_email) [oauth]"
    # Display updated account list
    cmd_list
    echo ""
    echo "Please restart Claude Code to use the new authentication."
    echo ""
}

# Perform switch to API account
perform_switch_to_api() {
    local target_account="$1"
    
    # Get current account info
    local current_account current_email
    current_account=$(jq -r '.activeAccountNumber' "$SEQUENCE_FILE")
    current_email=$(get_current_account)
    
    # If current account is OAuth, backup it first
    local current_type
    current_type=$(get_account_type "$current_account")
    
    if [[ "$current_type" == "oauth" && -n "$current_account" && "$current_account" != "null" && "$current_email" != "none" ]]; then
        local current_creds current_config
        current_creds=$(read_credentials)
        current_config=$(cat "$(get_claude_config_path)")
        
        write_account_credentials "$current_account" "$current_email" "$current_creds"
        write_account_config "$current_account" "$current_email" "$current_config"
    fi
    
    # Setup API environment
    setup_api_environment "$target_account"
    
    # Get account name
    local account_name
    account_name=$(jq -r --arg num "$target_account" '.accounts[$num].email' "$SEQUENCE_FILE")
    
    # Update state
    local updated_sequence
    updated_sequence=$(jq --arg num "$target_account" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" '
        .activeAccountNumber = ($num | tonumber) |
        .lastUpdated = $now
    ' "$SEQUENCE_FILE")
    
    write_json "$SEQUENCE_FILE" "$updated_sequence"
    
    echo ""
    echo "Switched to Account-$target_account ($account_name) [api]"
    # Display updated account list
    cmd_list
    echo ""
    echo "API account activated!"
    echo ""
    echo "Environment variables have been added to your shell profile and will be available"
    echo "in all new terminal sessions."
    echo ""
    echo "To activate in your current terminal session, run:"
    echo "  eval \"\$(./ccswitch.sh --env-setup)\""
    echo ""
    echo "Or simply use the wrapper function (add to your shell profile for convenience):"
    echo "  ccswitch() { ./ccswitch.sh \"\$@\" && [[ -f ~/.claude/.api_env ]] && source ~/.claude/.api_env; }"
    echo ""
    echo "After activation, restart Claude Code to use the new API configuration."
    echo ""
}

# Output environment setup commands for eval
cmd_env_setup() {
    local env_file="$HOME/.claude/.api_env"
    
    # Check if API env file exists
    if [[ ! -f "$env_file" ]]; then
        # No API account active, clear any existing env vars
        echo "unset ANTHROPIC_BASE_URL ANTHROPIC_AUTH_TOKEN"
        return 0
    fi
    
    # Source the env file and output the exports
    # Read and output the exports from the file
    grep "^export" "$env_file" 2>/dev/null || true
}

# Show usage
show_usage() {
    echo "Multi-Account Switcher for Claude Code"
    echo "Usage: $0 [COMMAND]"
    echo ""
    echo "Commands:"
    echo "  --add-account                    Add current OAuth account to managed accounts"
    echo "  --add-api-account [name]        Add API account from ANTHROPIC_BASE_URL and ANTHROPIC_AUTH_TOKEN"
    echo "  --remove-account <num|email>    Remove account by number or email"
    echo "  --list                           List all managed accounts"
    echo "  --switch                         Rotate to next account in sequence"
    echo "  --switch-to <num|email>          Switch to specific account number or email"
    echo "  --env-setup                      Output environment setup commands (use with eval)"
    echo "  --help                           Show this help message"
    echo ""
    echo "Examples:"
    echo "  # Add OAuth account (must be logged in to Claude Code first)"
    echo "  $0 --add-account"
    echo ""
    echo "  # Add API account (requires environment variables)"
    echo "  export ANTHROPIC_BASE_URL='https://api.example.com'"
    echo "  export ANTHROPIC_AUTH_TOKEN='your-api-token'"
    echo "  $0 --add-api-account \"My Custom API\""
    echo ""
    echo "  # List and switch accounts"
    echo "  $0 --list"
    echo "  $0 --switch"
    echo "  $0 --switch-to 2"
    echo "  $0 --switch-to user@example.com"
    echo "  $0 --remove-account user@example.com"
    echo ""
    echo "  # For one-command switching with immediate activation (API accounts):"
    echo "  eval \"\$($0 --switch-to 2 && $0 --env-setup)\""
    echo ""
    echo "  # Or add this function to your shell profile for convenience:"
    echo "  ccswitch() {"
    echo "    ./ccswitch.sh \"\$@\" && [[ -f ~/.claude/.api_env ]] && source ~/.claude/.api_env"
    echo "  }"
}

# Main script logic
main() {
    # Basic checks - allow root execution in containers
    if [[ $EUID -eq 0 ]] && ! is_running_in_container; then
        echo "Error: Do not run this script as root (unless running in a container)"
        exit 1
    fi
    
    check_bash_version
    check_dependencies
    
    case "${1:-}" in
        --add-account)
            cmd_add_account "oauth"
            ;;
        --add-api-account)
            shift
            cmd_add_account "api" "${1:-API Account}"
            ;;
        --remove-account)
            shift
            cmd_remove_account "$@"
            ;;
        --list)
            cmd_list
            ;;
        --switch)
            cmd_switch
            ;;
        --switch-to)
            shift
            cmd_switch_to "$@"
            ;;
        --env-setup)
            cmd_env_setup
            ;;
        --help)
            show_usage
            ;;
        "")
            show_usage
            ;;
        *)
            echo "Error: Unknown command '$1'"
            show_usage
            exit 1
            ;;
    esac
}

# Check if script is being sourced or executed
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi