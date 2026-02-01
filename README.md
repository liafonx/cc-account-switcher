# Multi-Account Switcher for Claude Code

A simple tool to manage and switch between multiple Claude Code accounts on macOS, Linux, and WSL.

## Features

- **Multi-account management**: Add, remove, and list Claude Code accounts
- **Quick switching**: Switch between accounts with simple commands
- **OAuth and API support**: Manage both Claude official subscription accounts (OAuth) and custom API endpoints
- **Persistent configuration**: API credentials are automatically added to your shell profile (.zshrc/.bashrc) for persistence across terminal sessions
- **IDE plugin support**: Works seamlessly with Claude Code IDE plugins (VS Code, JetBrains, etc.)
- **Cross-platform**: Works on macOS, Linux, and WSL
- **Secure storage**: Uses system keychain (macOS) or protected files (Linux/WSL)
- **Settings preservation**: Only switches authentication - your themes, settings, and preferences remain unchanged

## Installation

Download the script directly:

```bash
curl -O https://raw.githubusercontent.com/ming86/cc-account-switcher/main/ccswitch.sh
chmod +x ccswitch.sh
```

## Usage

### Basic Commands

```bash
# Add current OAuth account to managed accounts
./ccswitch.sh --add-account

# Add API account from environment variables
export ANTHROPIC_BASE_URL='https://api.example.com'
export ANTHROPIC_AUTH_TOKEN='your-api-token'
./ccswitch.sh --add-api-account "My Custom API"

# List all managed accounts
./ccswitch.sh --list

# Switch to next account in sequence
./ccswitch.sh --switch

# Switch to specific account by number or email
./ccswitch.sh --switch-to 2
./ccswitch.sh --switch-to user2@example.com

# Remove an account
./ccswitch.sh --remove-account user2@example.com

# Show help
./ccswitch.sh --help
```

### First Time Setup

#### OAuth Accounts (Claude Official Subscription)

1. **Log into Claude Code** with your first account (make sure you're actively logged in)
2. Run `./ccswitch.sh --add-account` to add it to managed accounts
3. **Log out** and log into Claude Code with your second account
4. Run `./ccswitch.sh --add-account` again
5. Now you can switch between accounts with `./ccswitch.sh --switch`
6. **Important**: After each switch, restart Claude Code to use the new authentication

#### API Accounts (Custom API Endpoints)

1. **Set environment variables** for your custom API:
   ```bash
   export ANTHROPIC_BASE_URL='https://your-api-endpoint.com'
   export ANTHROPIC_AUTH_TOKEN='your-api-token-here'
   ```
2. Run `./ccswitch.sh --add-api-account "My API Name"` to add the API account
3. Switch to this account: `./ccswitch.sh --switch-to <account_number>`
4. The environment variables are automatically added to your shell profile for persistence across terminal sessions

See the "Switching to an API Account" section below for details on activating the environment in your current session.

> **What gets switched:** Only your authentication credentials change. Your themes, settings, preferences, and chat history remain exactly the same.

## Requirements

- Bash 4.4+
- `jq` (JSON processor)

### Installing Dependencies

**macOS:**

```bash
brew install jq
```

**Ubuntu/Debian:**

```bash
sudo apt install jq
```

## Using API Accounts

API accounts allow you to use Claude Code with custom API endpoints instead of the official Claude subscription service.

### Adding an API Account

1. Set the required environment variables:
   ```bash
   export ANTHROPIC_BASE_URL='https://your-custom-api.com'
   export ANTHROPIC_AUTH_TOKEN='your-api-key-or-token'
   ```

   > **Security Note**: Setting tokens directly in your shell may expose them in your shell history. Consider using one of these safer alternatives:
   > - Prepend commands with a space if your shell has `HISTCONTROL=ignorespace` set (most Bash configurations)
   > - Use a password manager that can inject environment variables
   > - Read from a secure file: `export ANTHROPIC_AUTH_TOKEN=$(cat ~/.secrets/api_token)`
   > - Use a `.env` file that's gitignored: `source ~/.config/api.env`

2. Add the API account:
   ```bash
   ./ccswitch.sh --add-api-account "My Custom API"
   ```

### Switching to an API Account

When you switch to an API account, the script automatically:

1. **Updates your shell profile** (`.zshrc`, `.bashrc`, etc.) with the API environment variables
2. Creates a temporary environment file at `~/.claude/.api_env`

```bash
./ccswitch.sh --switch-to 2  # or use the account number from --list
```

**Persistence Across Terminal Sessions**:

The environment variables are automatically added to your shell profile, so they persist across terminal sessions. You have three options to activate them:

1. **Start a new terminal** (recommended for IDE plugins) - Variables are automatically available
2. **Reload your shell profile**: `source ~/.zshrc` (or `~/.bashrc` for Bash users)
3. **Source the API env file**: `source ~/.claude/.api_env` (temporary, current session only)

**Claude Code IDE Plugin Support**:

When using Claude Code as an IDE plugin (VS Code, JetBrains, etc.), the environment variables from your shell profile are automatically available. After switching accounts, simply:

- Restart your IDE, or
- Reload the IDE window

The plugin will automatically read `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN` from your environment.

### Switching Between OAuth and API Accounts

You can freely switch between OAuth accounts and API accounts. The script automatically:
- Backs up OAuth credentials when switching away from an OAuth account
- Clears API environment settings when switching away from an API account
- Restores the appropriate authentication for the target account

## How It Works

The switcher stores account authentication data separately:

- **OAuth Accounts**:
  - **macOS**: Credentials in Keychain, OAuth info in `~/.claude-switch-backup/`
  - **Linux/WSL**: Both credentials and OAuth info in `~/.claude-switch-backup/` with restricted permissions

- **API Accounts**:
  - API endpoint URL and authentication token stored in `~/.claude-switch-backup/api_accounts.json`
  - When switching to an API account:
    - Creates `~/.claude/.api_env` with environment variables for the current session
    - Updates your shell profile (`.zshrc`, `.bashrc`, etc.) for persistence across terminal sessions
  - Environment variables are automatically available to Claude Code and IDE plugins

When switching accounts, it:

1. Backs up the current account's authentication data (if OAuth)
2. Restores the target account's authentication data
3. For OAuth: Updates Claude Code's authentication files and removes API environment variables
4. For API: 
   - Sets up environment file at `~/.claude/.api_env`
   - Updates shell profile with `ANTHROPIC_BASE_URL` and `ANTHROPIC_AUTH_TOKEN`
   - Variables persist across terminal sessions and are available to IDE plugins

## Troubleshooting

### If a switch fails

- Check that you have accounts added: `./ccswitch.sh --list`
- Verify Claude Code is closed before switching
- Try switching back to your original account

### If you can't add an account

- Make sure you're logged into Claude Code first
- Check that you have `jq` installed
- Verify you have write permissions to your home directory

### If Claude Code doesn't recognize the new account

- Make sure you restarted Claude Code after switching
- Check the current account: `./ccswitch.sh --list` (look for "(active)")

## Cleanup/Uninstall

To stop using this tool and remove all data:

1. Note your current active account: `./ccswitch.sh --list`
2. Remove the backup directory: `rm -rf ~/.claude-switch-backup`
3. Delete the script: `rm ccswitch.sh`

Your current Claude Code login will remain active.

## Security Notes

- OAuth credentials stored in macOS Keychain or files with 600 permissions
- API credentials stored in files with 600 permissions (only readable by file owner):
  - `~/.claude-switch-backup/api_accounts.json` - Permanent storage of API credentials
  - `~/.claude/.api_env` - Active API environment file (created when switching to an API account)
- Authentication files are stored with restricted permissions (600)
- The tool requires Claude Code to be closed during account switches
- **Important**: API tokens are stored in plain text (with 600 permissions). Ensure your home directory is properly secured and encrypted.

## License

MIT License - see LICENSE file for details
