# Multi-Account Switcher for Claude Code

A simple command-line tool to manage and switch between multiple Claude Code accounts on macOS and Linux (including WSL).

## Features

- **One-command switching**: Single command to switch between OAuth and API accounts
- **OAuth and API support**: Manage both Claude official subscription accounts and custom API endpoints
- **Automatic activation**: API environment variables are automatically activated in your current shell
- **Persistent configuration**: Credentials persist across terminal sessions
- **Cross-platform**: Supports macOS and Linux
- **Secure storage**: Uses system keychain (macOS) or protected files (Linux)
- **Settings preservation**: Only switches authentication - themes, settings, and preferences remain unchanged

## Installation

### Quick Install (Recommended)

Install with a single command:

```bash
bash -c "$(curl -H 'Cache-Control: no-cache, no-store' -fsSL https://raw.githubusercontent.com/liafonx/cc-account-switcher/main/install.sh)"
```

This will:
- Check and install dependencies (jq)
- Download the latest version of ccswitch.sh
- Install to `~/.local/bin/ccswitch.sh`
- Set up the shell wrapper function automatically
- Add the installation directory to your PATH

After installation, reload your shell:
```bash
source ~/.zshrc  # or source ~/.bashrc
```

### Manual Installation

```bash
# Download the script
curl -O https://raw.githubusercontent.com/liafonx/cc-account-switcher/main/ccswitch.sh
chmod +x ccswitch.sh

# Move to a permanent location
mkdir -p ~/.local/bin
mv ccswitch.sh ~/.local/bin/ccswitch.sh

# Or install system-wide (requires sudo)
sudo mv ccswitch.sh /usr/local/bin/ccswitch.sh
```

### Setup Shell Wrapper

The quick install script automatically sets up the wrapper function. If you installed manually, add this wrapper to your shell profile for seamless account switching:

```bash
# Add to ~/.zshrc or ~/.bashrc
ccswitch() { ~/.local/bin/ccswitch.sh "$@" && [[ -f ~/.claude/.api_env ]] && source ~/.claude/.api_env; }
# Or if installed system-wide:
# ccswitch() { /usr/local/bin/ccswitch.sh "$@" && [[ -f ~/.claude/.api_env ]] && source ~/.claude/.api_env; }
```

Then reload: `source ~/.zshrc` (or `source ~/.bashrc`)

The wrapper automatically activates API environment variables after switching, making account changes take effect immediately.

## Usage

### Quick Switching

With the shell wrapper installed:

```bash
# Switch to a specific account by email or number
ccswitch --switch-to user@example.com
ccswitch --switch-to 2

# Rotate to next account
ccswitch --switch
```

### Managing Accounts

```bash
# Add current OAuth account
./ccswitch.sh --add-account

# Add API account (set environment variables first)
export ANTHROPIC_BASE_URL='https://api.example.com'
export ANTHROPIC_AUTH_TOKEN='your-api-token'
./ccswitch.sh --add-api-account "My Custom API"

# List all accounts
./ccswitch.sh --list

# Remove an account
./ccswitch.sh --remove-account user@example.com

# Show help
./ccswitch.sh --help
```

### Initial Setup

#### OAuth Accounts (Claude Official Subscription)

1. Log into Claude Code with your first account
2. Run `./ccswitch.sh --add-account` to save it
3. Log out and log into Claude Code with your second account
4. Run `./ccswitch.sh --add-account` again
5. Switch between accounts with `./ccswitch.sh --switch`
6. **Important**: Restart Claude Code after switching to activate the new authentication

#### API Accounts (Custom Endpoints)

1. Set environment variables for your custom API:
   ```bash
   export ANTHROPIC_BASE_URL='https://your-api-endpoint.com'
   export ANTHROPIC_AUTH_TOKEN='your-api-token'
   ```
2. Run `./ccswitch.sh --add-api-account "My API Name"`
3. Switch to the account: `./ccswitch.sh --switch-to <account_number>`
4. The environment variables are automatically added to your shell profile for persistence

> **Note**: Only authentication credentials change when switching. Your themes, settings, preferences, and chat history remain unchanged.

## Prerequisites

- **Bash 4.4+** (automatically checked during installation)
- **jq** (JSON processor - automatically installed by the install script)

### Manual jq Installation

If you're installing manually or the automatic installation fails:

```bash
# macOS
brew install jq

# Linux (Debian/Ubuntu)
sudo apt install jq

# Linux (Fedora/RHEL)
sudo dnf install jq

# Linux (Arch)
sudo pacman -S jq
```

### Custom API Endpoints

API accounts allow you to use Claude Code with custom API endpoints instead of the official Claude subscription.

**Adding an API Account:**

Set the required environment variables and add the account:
```bash
export ANTHROPIC_BASE_URL='https://your-custom-api.com'
export ANTHROPIC_AUTH_TOKEN='your-api-key-or-token'
./ccswitch.sh --add-api-account "My Custom API"
```

> **Security Tip**: Avoid exposing tokens in shell history:
> - Prepend commands with a space if `HISTCONTROL=ignorespace` is set
> - Use a password manager or secure file: `export ANTHROPIC_AUTH_TOKEN=$(cat ~/.secrets/api_token)`
> - Source from a gitignored .env file: `source ~/.config/api.env`

**Switching to API Accounts:**

With the wrapper function:
```bash
ccswitch --switch-to 2  # Automatically activates in current terminal
```

Without the wrapper:
```bash
./ccswitch.sh --switch-to 2
eval "$(./ccswitch.sh --env-setup)"  # Manual activation
```

When switching to an API account:
- API credentials are written to your shell profile (`.zshrc`/`.bashrc`) for persistence
- Environment variables are activated in your current terminal
- New terminal sessions automatically have the correct variables
- IDE plugins (VS Code, JetBrains) automatically use the environment variables after restart

## How It Works

The switcher stores account authentication data separately:

**OAuth Accounts:**
- **macOS**: Credentials in Keychain, OAuth info in `~/.claude-switch-backup/`
- **Linux/WSL**: Both credentials and OAuth info in `~/.claude-switch-backup/` with restricted permissions

**API Accounts:**
- API endpoint URL and token stored in `~/.claude-switch-backup/api_accounts.json`
- When active, creates `~/.claude/.api_env` with environment variables
- Updates your shell profile for persistence across sessions

When switching accounts:
1. Backs up the current account's authentication data (if OAuth)
2. Restores the target account's authentication data
3. For OAuth: Updates Claude Code's auth files and removes API environment variables
4. For API: Sets up environment file and updates shell profile with `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN`

## Troubleshooting

**Switch fails:**
- Check accounts exist: `./ccswitch.sh --list`
- Ensure Claude Code is closed before switching
- Try switching back to your original account

**Can't add account:**
- Make sure you're logged into Claude Code first
- Verify `jq` is installed
- Check write permissions to your home directory

**Claude Code doesn't recognize new account:**
- Restart Claude Code after switching
- Verify current account: `./ccswitch.sh --list` (look for "(active)")

## Security

- OAuth credentials stored in macOS Keychain or files with 600 permissions
- API credentials stored in files with 600 permissions (only readable by file owner):
  - `~/.claude-switch-backup/api_accounts.json` - Permanent storage
  - `~/.claude/.api_env` - Active environment file
- Authentication files have restricted permissions (600)
- **Important**: API tokens are stored in plain text (with 600 permissions). Ensure your home directory is properly secured and encrypted.

## Uninstall

To remove the tool:
1. Note your current active account: `./ccswitch.sh --list`
2. Remove backup directory: `rm -rf ~/.claude-switch-backup`
3. Delete the script: `rm /usr/local/bin/ccswitch.sh` (or wherever you installed it)
4. Remove the wrapper function from your shell profile

Your current Claude Code login will remain active.

## License

MIT License - see LICENSE file for details
