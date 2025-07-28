# LAM (LLM API Manager)

A secure and convenient command-line tool for managing LLM API keys and base URLs on Ubuntu/Linux systems. LAM allows you to securely store, manage, and quickly switch between different LLM API configurations with simple commands.

## Features

- 🔐 **Secure Storage**: All API keys are encrypted using AES-256-CBC encryption
- 🚀 **Quick Switching**: Instantly export API credentials to environment variables
- 🔧 **Multiple Providers**: Built-in support for OpenAI, Anthropic, **and** custom providers
- 📝 **CRUD Operations**: Add, list, edit, delete, and show API configurations
- 🕒 **Session Management**: Convenient session timeout to avoid repeated password entry
- 🎯 **Interactive Setup**: Guided prompts for easy configuration
- 🛡️ **Security First**: Master password protection with secure file permissions

## Installation

### Prerequisites

Make sure you have the required dependencies installed:

```bash
sudo apt-get update
sudo apt-get install jq openssl
```

### Install the Tool

1. **Clone or download** this repository
2. **Run the installation script**:

```bash
# For system-wide installation (requires sudo)
sudo ./install.sh

# For user-only installation
./install.sh
```

3. **Initialize the tool**:

```bash
lam init
```

## Quick Start

### 1. Initialize the Tool

```bash
lam init
```

LAM will explain the master password setup and prompt you to create one. This password encrypts all your API keys with AES-256-CBC encryption.

### 2. Add Your First API Configuration

```bash
lam add openai-gpt4
```

Follow the structured prompts to enter:
- API Key (e.g., OPENAI_API_KEY=sk-your-key)
- Base URL (e.g., OPENAI_BASE_URL=https://api.openai.com/v1)
- Additional variables (optional, e.g., MODEL_NAME=gpt-4)
- Model name (optional)
- Description (optional)

### 3. List Your Configurations

```bash
lam list
```

### 4. Use a Configuration

```bash
# Simply activate a profile - no complex syntax needed!
lam use openai-gpt4

# Check what's active
lam status

# Test the connection
lam test

# Verify the variables are set
echo $OPENAI_API_KEY
echo $OPENAI_BASE_URL
```

## Commands Reference

### Basic Commands

| Command | Description | Example |
|---------|-------------|---------|
| `init` | Initialize the tool with master password | `lam init` |
| `add <name>` | Add new API configuration | `lam add my-openai` |
| `list` | List all configurations | `lam list` |
| `use <name>` | Activate configuration (export to environment) | `lam use my-openai` |
| `show <name>` | Show configuration details (masked values) | `lam show my-openai` |
| `edit <name>` | Edit existing configuration | `lam edit my-openai` |
| `delete <name>` | Delete configuration | `lam delete my-openai` |
| `status` | Show current active profile | `lam status` |
| `test` | Test API connection | `lam test` |
| `backup` | Backup all profiles | `lam backup` |
| `stats` | Show usage statistics | `lam stats` |
| `update` | Update LAM to latest version | `lam update` |
| `uninstall` | Completely remove LAM | `lam uninstall` |
| `--version` | Show version information | `lam --version` |
| `help` | Show help message | `lam help` |

### Environment Variables

LAM exports exactly the environment variables you configure using KEY=VALUE pairs:

#### Examples
- `OPENAI_API_KEY`, `OPENAI_BASE_URL`, `OPENAI_MODEL`
- `ANTHROPIC_API_KEY`, `ANTHROPIC_BASE_URL`, `ANTHROPIC_MODEL`  
- `API_KEY`, `BASE_URL`, `MODEL_NAME`
- Any custom variables you define (e.g., `CUSTOM_HEADER`, `TIMEOUT_SECONDS`)

#### Always Exported
- `LLM_CURRENT_PROFILE` - Name of the currently active profile
- `MODEL_NAME` - Model name (if specified during configuration)

## Usage Examples

### Example 1: OpenAI Configuration

```bash
# Add OpenAI configuration
lam add openai-gpt4

# When prompted, enter:
# API Key: OPENAI_API_KEY=sk-your-openai-key-here
# Base URL: OPENAI_BASE_URL=https://api.openai.com/v1
# Additional variables: (press Enter to skip)
# Model Name: gpt-4
# Description: OpenAI GPT-4 for production

# Use the configuration - simple!
lam use openai-gpt4

# Now you can use OpenAI API
curl -H "Authorization: Bearer $OPENAI_API_KEY" \
     -H "Content-Type: application/json" \
     -d '{"model":"gpt-4","messages":[{"role":"user","content":"Hello!"}]}' \
     $OPENAI_BASE_URL/chat/completions
```

### Example 2: Local Ollama Setup

```bash
# Add local Ollama configuration
lam add ollama-local

# When prompted, enter:
# API Key: API_KEY=not-needed
# Base URL: BASE_URL=http://localhost:11434/v1
# Additional variables: (press Enter to skip)
# Model Name: llama2:7b
# Description: Local Ollama instance

# Use the configuration
lam use ollama-local

# Test with local model
curl -H "Authorization: Bearer $API_KEY" \
     -H "Content-Type: application/json" \
     -d '{"model":"llama2:7b","messages":[{"role":"user","content":"Hello!"}]}' \
     $BASE_URL/chat/completions
```

### Example 3: Multiple Profiles Workflow

```bash
# Add multiple configurations
lam add openai-dev
lam add anthropic-prod
lam add local-testing

# List all profiles
lam list

# Switch between them as needed - super simple!
lam use openai-dev      # For development
lam use anthropic-prod  # For production
lam use local-testing   # For testing

# Check current status
lam status

# Test current connection
lam test
```

## Security Features

### Encryption
- All API keys are encrypted using AES-256-CBC
- Master password is used to derive encryption keys
- Configuration files have secure permissions (600)

### Session Management
- Session timeout of 1 hour for convenience
- Master password required after timeout
- Session files stored securely

### Best Practices
- Use strong master passwords (minimum 8 characters)
- Regularly rotate your API keys
- Keep your master password secure and private
- Use different profiles for different environments

## Configuration Storage

The tool stores its configuration in:
- **Config Directory**: `~/.config/lam/`
- **Encrypted Config**: `~/.config/lam/config.enc`
- **Session File**: `~/.config/lam/.session`

## Troubleshooting

### Common Issues

1. **"Command not found"**
   ```bash
   # Make sure the tool is in your PATH
   echo $PATH
   # Add to PATH if needed
   export PATH="$PATH:$HOME/.local/bin"
   ```

2. **"Failed to decrypt configuration"**
   - Check if you entered the correct master password
   - If you forgot the password, you'll need to reinitialize: `lam init`

3. **"Missing dependencies"**
   ```bash
   sudo apt-get install jq openssl
   ```

4. **Permission denied**
   ```bash
   chmod +x lam
   ```

### Update LAM

Keep LAM up to date with the latest features:

```bash
# Automatic update (requires curl and GitHub access)
lam update

# Manual update (for restricted networks)
# 1. Download latest code from GitHub
# 2. Extract and navigate to project directory  
# 3. Run: ./version_update.sh
```

### Uninstall LAM

Remove LAM completely from your system:

```bash
lam uninstall
```

### Reset Everything

If you need to start fresh:

```bash
# Remove all configuration
rm -rf ~/.config/lam/

# Reinitialize
lam init
```

## Version History

- **v3.0.0**: Universal key-value configuration, update system, uninstall command, enhanced UX
- **v2.0.0**: Major update with simplified commands, integrated features, and enhanced security  
- **v1.0.0**: Initial release

## Contributing

Feel free to submit issues, feature requests, or pull requests to improve this tool.

## License

This project is open source and available under the MIT License.

## Security Notice

This tool is designed for personal and development use. While it implements strong AES-256-CBC encryption, always follow your organization's security policies when handling API keys and sensitive credentials.