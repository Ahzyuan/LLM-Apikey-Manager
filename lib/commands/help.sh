#!/bin/bash

# LAM Tool Help & Version
# Functions: version, help

# Show version information
cmd_version() {
    local version_info
    local version_number
    local version_description
    
    version_info=$(get_version_info)
    version_number=$(echo "$version_info" | cut -d'|' -f1)
    version_description=$(echo "$version_info" | cut -d'|' -f2)
    
    echo "LAM (LLM API Manager) v${version_number}"
    if [[ -n "$version_description" ]]; then
        echo "$version_description"
    fi
}

# Show help
cmd_help() {
    echo "LAM (LLM API Manager) v$(get_version_info | cut -d'|' -f1) - Secure management of LLM API credentials"
    echo
    cat << 'EOF'
USAGE:
    lam <command> [arguments]

COMMANDS:
    • init                    Initialize/Reset the master password
    • add <name>              Add new API profile
    • list, ls                List all profiles
    • show <name>             Show profile details
    • use <name>              Export profile to environment variables
    • edit <name>             Edit existing profile
    • delete, del <name>      Delete specific profile
    • status                  Show LAM status and statistics
    • backup <action>         Comprehensive backup management
      ├─ create [name]         • Create backup (optionally with custom name)
      ├─ list, ls              • List all available backups
      ├─ info <file>           • Show detailed backup information
      ├─ load <file>           • Load configuration from backup
      ├─ delete, del <file>    • Delete a backup file
      └─ help, -h              • Show backup management help
    • update                  Upgrade LAM to latest version
    • uninstall               Completely remove LAM from system
    • help, -h                Show this help message
    • version, -v             Show version information

For detailed examples and usage, refer to: https://github.com/Ahzyuan/LLM-Apikey-Manager 🚀.
Looking forward to your star ⭐, feedback 💬 and contributions 🤝!
EOF
}