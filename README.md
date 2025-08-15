# 𝑳𝑨𝑴 (𝑳𝑳𝑴 𝑨𝑷𝑰-𝒌𝒆𝒚 𝑴𝒂𝒏𝒂𝒈𝒆𝒓)           

```
                                / /        // | |     /|    //| | 
                               / /        //__| |    //|   // | | 
                              / /        / ___  |   // |  //  | | 
                             / /        //    | |  //  | //   | | 
                            / /____/ / //     | | //   |//    | | 
```

A <ins>𝒍𝒊𝒕𝒆, 𝒔𝒆𝒄𝒖𝒓𝒆, 𝒐𝒖𝒕-𝒐𝒇-𝒃𝒐𝒙 𝒄𝒐𝒎𝒎𝒂𝒏𝒅-𝒍𝒊𝒏𝒆 𝒕𝒐𝒐𝒍</ins> for   

- **storing** your LACP<sup>(LACP = LLM API Credentials and Profiles)</sup> securely
- **managing** your LACP easily 
- **switching** between your LACP quickly
- **backing up and migrating** your LACP to new machines efficiently

> If you have 𝒎𝒖𝒍𝒕𝒊𝒑𝒍𝒆 𝑳𝑳𝑴 𝑨𝑷𝑰 𝒌𝒆𝒚𝒔 for an AI tool *(e.g., Claude Code)*,    
> this is designed for you.

## 𝒜. 𝒦𝑒𝓎 𝐹𝑒𝒶𝓉𝓊𝓇𝑒𝓈 ✨

<details>
<summary>🔐 Secure API Key Storage</summary>

- **Sensitive credential encryption** - keeps your API keys safe from leaking
- **Master password protection** - only you can access your credentials
- **Session management** - stay logged in for 30 minutes, then require master password to unlock for sensitive operations (including using, editing, deleting profiles...)

</details>

<details>
<summary>💼 Multiple Profile Managemen</summary>

- **Organize by project** - separate API keys for development, staging, and production
- **Quick switching** - instantly load different configurations
- **Easy editing** - update API keys and settings without starting over

</details>

<details>
<summary>🔄 Practical Backups</summary>

- **Never lose your data** - automatic encrypted backups of all your profiles
- **Easy restore** - recover your API keys if something goes wrong
- **Portable backups** - move your configurations between machines

</details>

<details>
<summary>⚡ Simple & Fast</summary>

- **One command setup** - get started in seconds with `lam init`
- **Works everywhere** - integrates seamlessly with your existing scripts and tools

</details>

## 𝐵. 𝐼𝓃𝓈𝓉𝒶𝓁𝓁𝒶𝓉𝒾𝑜𝓃 🔧

| Linux | macOS | Windows |
|:--:|:--:|:--:|
| ✔ | ✔ | ✔(use [WSL](https://learn.microsoft.com/en-gb/windows/wsl/install)) |

```bash
# Clone the repository
git clone https://github.com/Ahzyuan/LLM-Apikey-Manager.git
cd LLM-Apikey-Manager

# Install dependencies (Ubuntu/Debian)
sudo apt-get update
sudo apt-get install -y sqlite3 openssl curl tar jq

# Install LAM
sudo bash install.sh # system-wise installation
# or
bash install.sh # user-wise installation
```

## 𝒞. 𝒬𝓊𝒾𝒸𝓀 𝒮𝓉𝒶𝓇𝓉 🚀

<details>
<summary>1. 𝑰𝒏𝒊𝒕𝒊𝒂𝒍 𝑺𝒆𝒕𝒖𝒑</summary>

```bash
# Initialize LAM (first time only)
lam init
# You'll be prompted to create a master password (8-256 characters)
```

</details>

<details>
<summary>2. 𝑷𝒓𝒐𝒇𝒊𝒍𝒆 𝑴𝒂𝒏𝒂𝒈𝒆𝒎𝒆𝒏𝒕</summary>

```bash
# Add a new API profile
lam add claude-sonnet4
# Interactive prompts will guide you through:
# - Model name (e.g., "gpt-4", "claude-3", "llama-2")
# - Description (optional)
# - Environment variables (API_KEY, BASE_URL, etc.)

# List all profiles
lam list # or lam ls

# Show detailed profile information
lam show claude-sonnet4

# Export profile API credential to current shell environment
lam use claude-sonnet4
# This sets environment variables you defined in your profile, like:
# ANTHROPIC_API_KEY=your-API-Key
# ANTHROPIC_BASE_URL=https://api.moonshot.cn/anthropic

# Edit existing profile
lam edit claude-sonnet4

# Delete a profile
lam delete claude-sonnet4
```

</details>

<details>
<summary>3. 𝑩𝒂𝒄𝒌𝒖𝒑 𝑴𝒂𝒏𝒂𝒈𝒆𝒎𝒆𝒏𝒕</summary>

```bash
# Create a backup
lam backup create [backup-name]

# List all backups
lam backup list # or lam backup ls

# Show details of a backup
lam backup info [backup-name]

# Restore from backup
lam backup load [backup-name]

# Delete a backup
lam backup delete [backup-name] # or lam backup del [backup-name]

# Help message for backup
lam backup help # or lam backup -h
```

</details>

<details>
<summary>4. 𝑻𝒐𝒐𝒍 𝑴𝒂𝒏𝒂𝒈𝒆𝒎𝒆𝒏𝒕</summary>

```bash
# Show LAM status
lam status

# Update LAM
lam update

# Uninstall LAM
lam uninstall

# Help message
lam help # or lam -h

# Version info
lam version # or lam -v
```

</details>

> [!NOTE]
> 
> While `LAM` aims to offer a secure LLM API management tool, no system is completely secure, so please：
> 1. **Don't rely solely on LAM to store your API keys**: make sure to keep additional backups out of `LAM`.
> 2. **Frequently backup your profiles**: you can use the `lam backup create` command to create backups, and it's best to save the backup files in multiple locations.

## 𝑫. 𝑪𝒐𝒎𝒎𝒂𝒏𝒅 𝑹𝒆𝒇𝒆𝒓𝒆𝒏𝒄𝒆 📋

```bash
# Profile Management
lam add <name>              # Add new API profile
lam list, ls                # List all profiles
lam show <name>             # Show profile details
lam use <name>              # Export profile to environment
lam edit <name>             # Edit existing profile
lam delete, del <name>      # Delete specific profile

# Backup Management
lam backup create [name]    # Create backup
lam backup list, ls         # List all backups
lam backup info <file>      # Show backup information
lam backup load <file>      # Restore from backup
lam backup delete <file>    # Delete a backup
lam backup help, -h         # Show backup help

# System Operations
lam init                    # Initialize/Reset master password
lam status                  # Show LAM status and statistics
lam update                  # Update to latest version
lam uninstall               # Completely remove LAM
lam help, -h                # Show help message
lam version, -v             # Show version information
```

## 🤝 Contributing

We welcome contributions to make LAM even better!   
Please follow our [Contributing Guidelines](CONTRIBUTING.md) to get started.

## 📄 License

This project is licensed under the **Apache-2.0** License. See the [LICENSE](LICENSE) file for details.