#!/usr/bin/env bash

# LAM Backup Commands
# All backup management functionality

# Main backup command dispatcher with subcommand routing
# Arguments:
#   $1 - action: Backup action (create, list, info, load, delete, help)
#   $2 - target: Target file or name (optional, depends on action)
# Returns:
#   0 on success, 1 on failure
# Globals:
#   Routes to appropriate backup functions
cmd_backup() {
    local action="${1:-help}"
    local backup_name="${2:-}"
    
    case "$action" in
        "create")
            backup_create "$backup_name"
            ;;
        "list"|"ls")
            backup_list
            ;;
        "info")
            backup_info "$backup_name"
            ;;
        "load")
            backup_load "$backup_name"
            ;;
        "delete"|"del")
            backup_delete "$backup_name"
            ;;
        "help"|"-h")
            backup_help
            ;;
        *)
            log_error "Invalid backup action: $action"
            backup_help
            return 1
            ;;
    esac
}

# Interactive selection helper for backup operations
# Arguments:
#   $1 - prompt: Prompt message for selection
#   $2 - options: Array of options to choose from
# Returns:
#   0 on success, outputs selected option to stdout; 1 on failure
# Globals:
#   None
_interactive_selection() {
    local backup_file="$1"
    local backup_dir="$HOME/.lam-backups"
    local backup_path="$backup_dir/$backup_file"
    
    # Check if backup directory exists
    if [[ ! -d "$backup_dir" ]]; then
        log_info "No backups found."
        log_info "Use ${PURPLE}'lam backup create [name]'${NC} to create your first backup."
        exit 1
    fi
    
    # Get available backup files
    local backup_files=()
    for file in "$backup_dir"/*.tar.gz; do
        if [[ -f "$file" ]]; then
            backup_files+=("$(basename "$file")")
        fi
    done
    
    if [[ ${#backup_files[@]} -gt 0 ]]; then
        mapfile -t backup_files < <(printf "%s
" "${backup_files[@]}" | sort -r)
        unset IFS
    elif [[ ${#backup_files[@]} -eq 0 ]]; then
        log_error "No backup files found in $backup_dir"
        log_info "Use ${PURPLE}'lam backup create [name]'${NC} to create your first backup."
        exit 1
    fi
    
    # Handle backup file selection
    if [[ ! -f "$backup_path" ]]; then
        if [[ -n "$backup_file" ]]; then
            log_error "Backup file not found: ${PURPLE}$backup_file${NC}"
            echo >&2
        else
            log_error "Backup filename is required"
            echo >&2
        fi
        
        log_info "Available backup files:"
        for ((i=0; i<${#backup_files[@]}; i++)); do
            echo "  $((i+1)). ${backup_files[i]}" >&2
        done
        echo >&2
        echo -en "Select a backup by number (1-${#backup_files[@]}), or press Enter to cancel: " >&2
        local selection
        if ! read -r selection; then
            log_error "Failed to read selection"
            exit 1
        fi
        
        if [[ -z "$selection" ]]; then
            log_info "Operation cancelled."
            exit 0
        fi
        
        if [[ ! "$selection" =~ ^[0-9]+$ ]] || [[ "$selection" -lt 1 ]] || [[ "$selection" -gt ${#backup_files[@]} ]]; then
            log_error "Invalid selection. Please choose a number between 1 and ${#backup_files[@]}."
            exit 1
        fi
        
        backup_file="${backup_files[$((selection-1))]}"
        backup_path="$backup_dir/$backup_file"
        log_info "Selected backup: ${PURPLE}$backup_file${NC}"
        echo >&2
    fi

    echo "$backup_path"
}

# Create a new encrypted backup of all profiles and configuration
# Arguments:
#   $1 - backup_name: Custom backup name (optional)
# Returns:
#   0 on success, 1 on failure
# Globals:
#   CONFIG_DIR, BACKUP_DIR: Source and destination directories
backup_create() {
    local backup_name="$1"
    
    # Generate backup filename
    local backup_file
    if [[ -n "$backup_name" ]]; then
        # Validate custom backup name
        if [[ ! "$backup_name" =~ ^[a-zA-Z0-9._-]+$ ]]; then
            log_error "Invalid backup name ${PURPLE}$backup_name${NC}. Use only alphanumeric characters, dots, dashes, and underscores."
            return 1
        fi
        backup_file="${backup_name}-$(date +%Y%m%d-%H%M%S).tar.gz"
    else
        backup_file="lam-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    fi
    
    # Create backup directory if it doesn't exist
    local backup_dir="$HOME/.lam-backups"
    if [[ ! -d "$backup_dir" ]]; then
        if ! mkdir -p "$backup_dir"; then
            log_error "Failed to create backup directory: ${PURPLE}$backup_dir${NC}"
            log_info "Please check your permissions and try again."
            log_info "Or you can manually create it by running: ${PURPLE}mkdir -p $backup_dir && chmod 700 $backup_dir${NC}"
            return 1
        fi
        chmod 700 "$backup_dir"
    fi
    
    local backup_path="$backup_dir/$backup_file"
    
    log_info "Creating backup..."
    
    local profile_count
    profile_count=$(get_profile_count)
    if [ "$profile_count" -eq 0 ]; then
        log_info "No profiles found. Skipping backup..." 
        exit 0
    fi
        
    local profile_details="[]"
    local profile_names profile_names_list
    profile_names=$(get_profile_names)
    profile_names_list=$(echo "$profile_names" | tr '\n' ',' | sed 's/,$//')
    
    while IFS= read -r profile_name; do
        local profile_json
        profile_json=$(get_profile "$profile_name")
        
        local profile_detail
        profile_detail=$(echo "$profile_json" | jq -c \
            --arg name "$profile_name" \
            '{
                name: $name,
                env_var_names: (.env_vars | keys),
                model_name: (.model_name // "not specified"),
                description: (.description // "no description"),
                created: (.created // "unknown")
            }' 2>/dev/null)
        
        if [[ -n "$profile_detail" ]]; then
            profile_details=$(echo "$profile_details" | jq --argjson detail "$profile_detail" '. += [$detail]' 2>/dev/null)
        fi
    done <<< "$profile_names"
    
    # Create backup with metadata
    local temp_dir
    if ! temp_dir=$(mktemp -d); then
        log_error "Failed to create temporary directory"
        return 1
    fi
    TEMP_DIRS+=("$temp_dir")
    
    # Copy configuration
    cp -r "$CONFIG_DIR" "$temp_dir/lam-config"
    
    # Create metadata file with profile information using jq for proper JSON escaping
    local backup_metadata
    backup_metadata=$(jq -n \
        --arg backup_created "$(date -Iseconds)" \
        --arg lam_version "$(get_version_info | cut -d'|' -f1)" \
        --arg profile_count "$profile_count" \
        --arg backup_name "$backup_name" \
        --arg original_config_dir "$CONFIG_DIR" \
        --arg profile_names_list "$profile_names_list" \
        --argjson profile_details "$profile_details" \
        '{
            backup_created: $backup_created,
            lam_version: $lam_version,
            profile_count: ($profile_count | tonumber),
            backup_name: $backup_name,
            original_config_dir: $original_config_dir,
            profile_names: $profile_names_list,
            profile_details: $profile_details
        }')
    
    echo "$backup_metadata" > "$temp_dir/lam-config/backup-metadata.json"
        
    # Create the backup archive
    echo
    if tar -czf "$backup_path" -C "$temp_dir" "lam-config" 2>/dev/null; then
        log_success "Backup created: ${PURPLE}$backup_file${NC}"
        log_success "Location: ${PURPLE}$backup_path${NC}"
        log_success "Profiles backed up: ${PURPLE}$profile_count${NC}"
        echo
        log_info "💡 Backup Management Commands:"
        log_gray "• List all backups: lam backup list"
        log_gray "• Restore this backup: lam backup restore $backup_file"
        log_gray "• Show backup details: lam backup info $backup_file"
    else
        log_error "Failed to create backup archive"
        log_info "Possible causes and solutions:"
        log_info "• Check if you have write permissions in ${PURPLE}$backup_dir${NC}"
        log_info "• Ensure sufficient disk space is available"
        log_info "• Check if tar command is available: ${PURPLE}which tar${NC}"
        return 1
    fi
}

# List all available backups with detailed information
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
# Globals:
#   BACKUP_DIR: Directory containing backup files
backup_list() {
    local backup_dir="$HOME/.lam-backups"
    
    if [[ ! -d "$backup_dir" ]]; then
        log_info "No backups found."
        log_info "Create your first backup with: ${PURPLE}lam backup create [name]${NC}"
        return 0
    fi
    
    local backups
    backups=$(find "$backup_dir" -name "*-*.tar.gz" -type f 2>/dev/null | sort -r)
    
    if [[ -z "$backups" ]]; then
        log_info "No backups found in ${PURPLE}$backup_dir${NC}"
        log_info "Create your first backup with: ${PURPLE}lam backup create [name]${NC}"
        return 0
    fi
    
    echo -e "${BLUE}Available LAM Backups${NC}"
    echo "====================="
    echo
    
    while IFS= read -r backup_path; do
        local backup_file
        backup_file=$(basename "$backup_path")

        local backup_size
        backup_size=$(du -h "$backup_path" 2>/dev/null | cut -f1)

        local backup_date
        backup_date=$(stat -c %y "$backup_path" 2>/dev/null | cut -d"." -f1)

        log_purple "📦 $backup_file"
        
        local metadata
        if metadata=$(tar -xzOf "$backup_path" "lam-config/backup-metadata.json"); then
            local profile_count lam_version
            profile_count=$(echo "$metadata" | jq -r '.profile_count')
            lam_version=$(echo "$metadata" | jq -r '.lam_version')
            
            log_gray " ├─ Profiles: $profile_count"
            log_gray " ├─ LAM Version: $lam_version"
        fi
        
        log_gray " ├─ Size: $backup_size"
        log_gray " └─ Created: $backup_date"
        echo

    done <<< "$backups"
    
    log_info "💡 More Operations:"
    log_gray "• Restore a backup: lam backup restore <filename>"
    log_gray "• Show detailed info: lam backup info <filename>"
    log_gray "• Delete a backup: lam backup delete <filename>"
}

# Show detailed information about a specific backup
# Arguments:
#   $1 - backup_file: Backup file to analyze (optional, prompts if not provided)
# Returns:
#   0 on success, 1 on failure
# Globals:
#   BACKUP_DIR: Directory containing backup files
backup_info() {
    local backup_file="$1"
    local backup_path
    
    backup_path=$(_interactive_selection "$backup_file")
    if [[ -z "$backup_path" ]]; then
        return 0
    fi
    backup_file=$(basename "$backup_path")
    
    echo -e "${BLUE}Backup Information${NC}"
    echo "=================="
    echo -e "${PURPLE}• File${NC}: $backup_file"
    echo -e "${PURPLE}• Path${NC}: $backup_path"
    
    # Basic file information
        local backup_size
        backup_size=$(du -h "$backup_path" 2>/dev/null | cut -f1)

        local backup_date
        backup_date=$(stat -c %y "$backup_path" 2>/dev/null | cut -d"." -f1)
    
    echo -e "${PURPLE}• Created${NC}: $backup_date"
    echo -e "${PURPLE}• Size${NC}: $backup_size"
    
    # Try to extract and show metadata
    local metadata
    if metadata=$(tar -xzOf "$backup_path" "lam-config/backup-metadata.json"); then
        if echo "$metadata" | jq empty 2>/dev/null; then
            local lam_version ori_cfgdir profile_details
            lam_version=$(echo "$metadata" | jq -r '.lam_version // "unknown"')
            ori_cfgdir=$(echo "$metadata" | jq -r '.original_config_dir // "unknown"')
            profile_details=$(echo "$metadata" | jq -r '.profile_details // empty')
            echo -e "${PURPLE}• LAM Version${NC}: $lam_version"
            echo -e "${PURPLE}• Original Config${NC}: $ori_cfgdir"
                    
            if [[ -n "$profile_details" && "$profile_details" != "null" && "$profile_details" != "[]" ]]; then
                echo 
                echo -e "${BLUE}Profiles in Selected Backup${NC}"
                echo "==========================="
                local profile_count
                profile_count=$(echo "$profile_details" | jq length || echo 0)
                
                for ((i=0; i<profile_count; i++)); do
                    local profile
                    profile=$(echo "$profile_details" | jq ".[$i]")
                    
                    if [[ -n "$profile" && "$profile" != "null" ]]; then
                        local name model_name description created env_vars
                        name=$(echo "$profile" | jq -r '.name // "unknown"')
                        model_name=$(echo "$profile" | jq -r '.model_name // "not specified"')
                        description=$(echo "$profile" | jq -r '.description // "no description"')
                        env_vars=$(echo "$profile" | jq -r '.env_var_names | join(", ")' || echo "none")
                        created=$(echo "$profile" | jq -r '.created // "unknown"')
                        
                        log_gray "${PURPLE}• Profile-$((i+1)): $name${NC}"
                        log_gray "├─ Model Name: $model_name"
                        log_gray "├─ Description: $description"
                        log_gray "├─ Environment Variables: $env_vars"
                        log_gray "└─ Created: $created"
                        echo
                    fi
                done
            fi
        else
            echo -e "${PURPLE}• Metadata${NC}: corrupted or invalid format"
        fi
        
    else
        echo
        log_error "Extracting metadata from backup file failed."
        return 1
    fi
}

# Load configuration from backup with validation and confirmation
# Arguments:
#   $1 - backup_file: Backup file to restore (optional, prompts if not provided)
# Returns:
#   0 on success, 1 on failure
# Globals:
#   CONFIG_DIR, BACKUP_DIR: Target and source directories
backup_load() {
    local backup_file="$1"
    local backup_path

    backup_path=$(_interactive_selection "$backup_file")
    if [[ -z "$backup_path" ]]; then
        return 0
    fi
    backup_file=$(basename "$backup_path")
    
    # Show backup information
    backup_info "$backup_file"
    echo
    
    # Confirm restoration
    log_warning "⚠️  This will replace your current LAM configuration!"
    log_warning "All your current profiles and settings will be lost."
    echo
    if ! get_verified_master_password "${GRAY}Verify your ${RED}master password${GRAY} to restore this backup: ${NC}" >/dev/null; then
        exit 1
    fi
    
    echo
    
    local temp_dir
    if ! temp_dir=$(mktemp -d); then
        log_error "Failed to create temporary directory"
        return 1
    fi
    TEMP_DIRS+=("$temp_dir")
    
    if ! tar -xzf "$backup_path" -C "$temp_dir" 2>/dev/null; then
        log_error "Failed to extract backup archive"
        return 1
    fi
        
    # Restore configuration
    if [[ -d "$temp_dir/lam-config" ]]; then
        if [[ -d "$CONFIG_DIR" ]]; then
            rm -rf "$CONFIG_DIR" || {
                log_error "Failed to remove existing configuration directory"
                log_info "Please ensure you have permission to delete ${PURPLE}$CONFIG_DIR${NC}"
                return 1
            }
        fi
        cp -r "$temp_dir/lam-config" "$CONFIG_DIR"
        rm -f "$CONFIG_DIR/backup-metadata.json"
    else
        log_error "Backup file corrupted and does not contain a valid configuration."
        return 1
    fi
    
    chmod 700 "$CONFIG_DIR"
    find "$CONFIG_DIR" -type f -exec chmod 600 {} \;
    
    log_success "Backup restored successfully!"
    log_success "Your LAM configuration has been restored from: ${PURPLE}$backup_file${NC}"
}

# Delete a backup file with confirmation
# Arguments:
#   $1 - backup_file: Backup file to delete (optional, prompts if not provided)
# Returns:
#   0 on success, 1 on failure
# Globals:
#   BACKUP_DIR: Directory containing backup files
backup_delete() {
    local backup_file="$1"
    local backup_path
    
    backup_path=$(_interactive_selection "$backup_file")
    if [[ -z "$backup_path" ]]; then
        return 0
    fi
    backup_file=$(basename "$backup_path")
    
    # Show backup info before deletion
    backup_info "$backup_file"
    echo
    
    log_warning "⚠️  This action cannot be undone!"
    if ! get_verified_master_password "${GRAY}Verify your ${RED}master password${GRAY} to delete this backup: ${NC}" >/dev/null; then
        exit 1
    fi
    
    if rm -f "$backup_path"; then
        log_success "Backup deleted: $backup_file"
    else
        log_error "Failed to delete backup"
        log_info "Please check your permissions and try again."
        log_info "Or you can manually delete it by running ${PURPLE}'rm -f $backup_path'${NC}"
        exit 1
    fi
}

# Display comprehensive help for backup management
# Arguments:
#   None
# Returns:
#   Always returns 0
# Globals:
#   None
backup_help() {
    echo "LAM Backup Management"
    echo
    echo "USAGE:"
    echo "    lam backup <action> [arguments]"
    echo
    echo "ACTIONS:"
    echo "    • create [name]           Create a new backup (optionally with custom name)"
    echo "    • list, ls                List all available backups"
    echo "    • info <filename>         Show detailed backup information"
    echo "    • load <filename>         Load configuration from backup"
    echo "    • delete, del <filename>  Delete a backup file"
    echo "    • help, -h                Show this help message"
    echo
    echo "💡 NOTE"
    log_gray "• Backup files are stored in $HOME/.lam-backups/"
    log_gray "• Each backup file include all profiles, settings, and session data"
    log_gray "• Restoring a backup will replace your current configuration"
    echo
    echo "🔮 EXAMPLES"
    log_gray "lam backup create                    # Create backup with auto-generated name"
    log_gray "lam backup create my-bak             # Create backup with custom name"
    log_gray "lam backup list                      # List all backups"
    log_gray "lam backup info my-bak-20250730-143022.tar.gz"
    log_gray "lam backup load my-bak-20250730-143022.tar.gz"
    log_gray "lam backup delete my-bak-20250730-143022.tar.gz"
}