#!/usr/bin/env bash

# LAM Tool Help & Version
# Functions: version, help

# Get version information from VERSION file
# Arguments:
#   None
# Returns:
#   0 on success, outputs "version|description" to stdout
# Globals:
#   SCRIPT_DIR: Directory containing VERSION file
get_version_info() {
    local version_file
    version_file="$SCRIPT_DIR/VERSION"
    
    if [[ -f "$version_file" ]]; then
        local version_content
        version_content=$(cat "$version_file" 2>/dev/null) || {
            echo "unknown|"
            return 0
        }
        
        local version_number
        if ! version_number=$(echo "$version_content" | head -n1 | tr -d '[:space:]' 2>/dev/null); then
            version_number="unknown"
        fi

        local version_description
        if ! version_description=$(\
            echo "$version_content" | tail -n +2 2>/dev/null | \
            grep -v '^[[:space:]]*$' 2>/dev/null | head -n1 2>/dev/null\
        ); then
            version_description=""
        fi        

        echo "${version_number}|${version_description}"
    else
        # Don't log warnings for help/version commands - just return default
        echo "unknown|"
    fi
}

# Display LAM version information
# Arguments:
#   None
# Returns:
#   Always returns 0
# Globals:
#   Uses get_version_info function
cmd_version() {
    local version_info
    local version_number
    local version_description
    
    version_info=$(get_version_info)
    version_number=$(echo "$version_info" | cut -d'|' -f1)
    version_description=$(echo "$version_info" | cut -d'|' -f2)
    
    echo "LAM (LLM API-key Manager) v${version_number}"
    if [[ -n "$version_description" ]]; then
        echo "$version_description"
    fi
}

# Display comprehensive help information for LAM
# Arguments:
#   None
# Returns:
#   Always returns 0
# Globals:
#   Uses get_version_info function
cmd_help() {
    echo "LAM (LLM API-key Manager) v$(get_version_info | cut -d'|' -f1) - Secure management of LLM API credentials"
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