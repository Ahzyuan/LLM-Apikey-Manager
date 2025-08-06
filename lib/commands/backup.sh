#!/bin/bash

# LAM Backup Commands
# All backup management functionality

# Enhanced backup management system
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
            backup_restore "$backup_name"
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

# Create a new backup
backup_create() {
    local backup_name="$1"
    
    if [[ ! -d "$CONFIG_DIR" ]]; then
        log_error "No LAM configuration found to backup"
        log_info "This usually means LAM hasn't been initialized yet."
        log_info "To fix this:"
        log_info "• Run 'lam init' to initialize LAM with a master password"
        log_info "• Then add profiles using 'lam add <profile_name>'"
        log_info "• After that, you can create backups with 'lam backup create'"
        return 1
    fi
    
    # Generate backup filename
    local backup_file
    if [[ -n "$backup_name" ]]; then
        # Validate custom backup name
        if [[ ! "$backup_name" =~ ^[a-zA-Z0-9._-]+$ ]]; then
            log_error "Invalid backup name. Use only alphanumeric characters, dots, dashes, and underscores."
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
            log_error "Failed to create backup directory: $backup_dir"
            log_info "Please check your permissions and try again."
            log_info "Or you can manually create it by running:"
            log_gray "  mkdir -p $backup_dir && chmod 700 $backup_dir"
            return 1
        fi
        chmod 700 "$backup_dir"
    fi
    
    local backup_path="$backup_dir/$backup_file"
    
    log_info "Creating backup..."
    echo
    
    # Get current configuration for metadata
    local config
    if config=$(get_session_config 2>/dev/null); then
        local profile_count
        profile_count=$(echo "$config" | jq -r '.profiles | length' 2>/dev/null || echo "0")
        
        # Extract profile information
        local profile_names
        local profile_details
        profile_names=$(echo "$config" | jq -r '.profiles | keys[]' 2>/dev/null | tr '\n' ',' | sed 's/,$//')
        
        # Create profile details array with comprehensive info (without sensitive values)
        profile_details=$(echo "$config" | jq -c '.profiles | to_entries | map({
            name: .key,
            env_var_names: (.value.env_vars | keys),
            model_name: (.value.model_name // "not specified"),
            description: (.value.description // "no description"),
            created: (.value.created // "unknown")
        })' 2>/dev/null || echo '[]')
        
        # Create backup with metadata
        local temp_dir
        if ! temp_dir=$(mktemp -d); then
            log_error "Failed to create temporary directory"
            return 1
        fi
        TEMP_DIRS+=("$temp_dir")
        
        # Copy configuration
        cp -r "$CONFIG_DIR" "$temp_dir/lam-config"
        
        # Create metadata file with profile information
        cat > "$temp_dir/lam-config/backup-metadata.json" << EOF
{
    "backup_created": "$(date -Iseconds)",
    "lam_version": "$(get_version_info | cut -d'|' -f1)",
    "profile_count": $profile_count,
    "backup_name": "${backup_name:-auto}",
    "original_config_dir": "$CONFIG_DIR",
    "profile_names": "$profile_names",
    "profile_details": $profile_details
}
EOF
        
        # Create the backup archive
        if tar -czf "$backup_path" -C "$temp_dir" "lam-config" 2>/dev/null; then
            log_success "Backup created: $backup_file"
            log_info "Location: $backup_path"
            log_info "Profiles backed up: $profile_count"
            echo
            log_info "💡 Backup Management Commands:"
            log_gray "• List all backups: lam backup list"
            log_gray "• Restore this backup: lam backup restore $backup_file"
            log_gray "• Show backup details: lam backup info $backup_file"
        else
            log_error "Failed to create backup archive"
            log_info "Possible causes and solutions:"
            log_info "• Check if you have write permissions in $backup_dir"
            log_info "• Ensure sufficient disk space is available"
            log_info "• Check if tar command is available: which tar"
            return 1
        fi
    else
        # Fallback: simple backup without metadata
        if tar -czf "$backup_path" -C "$(dirname "$CONFIG_DIR")" "$(basename "$CONFIG_DIR")/" 2>/dev/null; then
            log_success "Backup created: $backup_file"
            log_info "Location: $backup_path"
            echo
            log_warning "Backup created without metadata (configuration not accessible)"
            log_info "To create a complete backup with metadata:"
            log_info "• Ensure your session is active by running 'lam status' first"
            log_info "• Then retry: lam backup create [name]"
            
        else
            log_error "Failed to create backup"
            log_info "Possible causes and solutions:"
            log_info "• Check if you have write permissions in $backup_dir"
            log_info "• Ensure sufficient disk space is available"
            log_info "• Check if tar command is available: which tar"
            return 1
        fi
    fi
}

# List all available backups
backup_list() {
    local backup_dir="$HOME/.lam-backups"
    
    if [[ ! -d "$backup_dir" ]]; then
        log_info "No backups found."
        log_info "Create your first backup with: lam backup create [name]"
        return 0
    fi
    
    local backups
    backups=$(find "$backup_dir" -name "*-*.tar.gz" -type f 2>/dev/null | sort -r)
    
    if [[ -z "$backups" ]]; then
        log_info "No backups found in $backup_dir"
        log_info "Create your first backup with: lam backup create [name]"
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
        backup_date=$(stat -c %y "$backup_path" 2>/dev/null | cut -d'.' -f1)

        log_purple "📦 $backup_file"
        
        # Try to extract metadata if available
        local metadata
        if metadata=$(tar -xzOf "$backup_path" "lam-config/backup-metadata.json" 2>/dev/null); then
            local profile_count
            profile_count=$(echo "$metadata" | jq -r '.profile_count' 2>/dev/null)
            local lam_version
            lam_version=$(echo "$metadata" | jq -r '.lam_version' 2>/dev/null)
            
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

# Show detailed backup information
backup_info() {
    local backup_file="$1"
    local backup_dir="$HOME/.lam-backups"
    local backup_path="$backup_dir/$backup_file"
    
    # Check if backup directory exists
    if [[ ! -d "$backup_dir" ]]; then
        log_error "Backup directory does not exist: $backup_dir"
        log_info "No backups have been created yet. Use 'lam backup create [name]' to create your first backup."
        exit 1
    fi
    
    # Get available backup files
    local backup_files
    backup_files=($(find "$backup_dir" -name "*.tar.gz" -type f -printf "%f\n" 2>/dev/null | sort -r))
    
    if [[ ${#backup_files[@]} -eq 0 ]]; then
        log_error "No backup files found in $backup_dir"
        log_info "Use 'lam backup create [name]' to create your first backup."
        exit 1
    fi
    
    # Handle backup file selection
    if [[ -z "$backup_file" ]] || [[ ! -f "$backup_path" ]]; then
        if [[ -n "$backup_file" ]]; then
            log_error "Backup file not found: $backup_file"
            echo
        else
            log_error "Backup filename is required"
            echo
        fi
        
        log_info "Available backup files:"
        for ((i=0; i<${#backup_files[@]}; i++)); do
            echo "  $((i+1)). ${backup_files[i]}"
        done
        echo
        echo -en "Select a backup by number (1-${#backup_files[@]}), or press Enter to cancel: "
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
        echo
        log_info "Selected backup: $backup_file"
        echo
    fi
    
    echo -e "${BLUE}Backup Information${NC}"
    echo "=================="
    echo -e "${PURPLE}• File${NC}: $backup_file"
    echo -e "${PURPLE}• Path${NC}: $backup_path"
    
    # Basic file information
    local backup_size
    backup_size=$(du -h "$backup_path" 2>/dev/null | cut -f1)
    local backup_date
    backup_date=$(stat -c %y "$backup_path" 2>/dev/null | cut -d'.' -f1)
    
    echo -e "${PURPLE}• Created${NC}: $backup_date"
    echo -e "${PURPLE}• Size${NC}: $backup_size"
    
    # Try to extract and show metadata
    local metadata
    if metadata=$(tar -xzOf "$backup_path" "lam-config/backup-metadata.json" 2>/dev/null); then
        echo -e "${PURPLE}• LAM Version${NC}: $(echo "$metadata" | jq -r '.lam_version')"
        echo -e "${PURPLE}• Original Config${NC}: $(echo "$metadata" | jq -r '.original_config_dir')"
                
        # Show profile details if available
        local profile_details
        profile_details=$(echo "$metadata" | jq -r '.profile_details // empty' 2>/dev/null)
        if [[ -n "$profile_details" && "$profile_details" != "null" && "$profile_details" != "[]" ]]; then
            echo 
            echo -e "${BLUE}Profile Details${NC}"
            echo "=================="
            # Parse and display each profile individually
            local profile_count
            profile_count=$(echo "$profile_details" | jq length 2>/dev/null || echo 0)
            
            for ((i=0; i<profile_count; i++)); do
                local profile
                profile=$(echo "$profile_details" | jq ".[$i]" 2>/dev/null)
                
                if [[ -n "$profile" && "$profile" != "null" ]]; then
                    local name model_name description created env_vars
                    name=$(echo "$profile" | jq -r '.name // "unknown"')
                    model_name=$(echo "$profile" | jq -r '.model_name // "not specified"')
                    description=$(echo "$profile" | jq -r '.description // "no description"')
                    env_vars=$(echo "$profile" | jq -r '.env_var_names | join(", ")' 2>/dev/null || echo "none")
                    created=$(echo "$profile" | jq -r '.created // "unknown"')
                    
                    log_gray "${PURPLE}• Profile-$((i+1)): $name${NC}"
                    log_gray "├─ Model Name: $model_name"
                    log_gray "├─ Description: $description"
                    log_gray "├─ Environment Variables: $env_vars"
                    log_gray "└─ Created: $created"
                    
                    # Add spacing between profiles (except for the last one)
                    if [[ $((i + 1)) -lt $profile_count ]]; then
                        echo
                    fi
                fi
            done
        fi
        
    else
        echo
        log_info "No metadata available, the profile details are inaccessible."
        log_info "To create a complete backup with metadata:"
        log_info "• Ensure your session is active by running 'lam status' first"
        log_info "• Then retry: lam backup create [name]"
    fi
}

# Restore a backup
backup_restore() {
    local backup_file="$1"
    
    if [[ -z "$backup_file" ]]; then
        log_error "Backup filename is required"
        echo "Usage: lam backup restore <backup_filename>"
        echo
        log_info "Available backups:"
        backup_list
        return 1
    fi
    
    local backup_dir="$HOME/.lam-backups"
    local backup_path="$backup_dir/$backup_file"
    
    # Check if backup exists
    if [[ ! -f "$backup_path" ]]; then
        log_error "Backup file not found: $backup_file"
        echo
        log_info "Available backups:"
        backup_list
        return 1
    fi
    
    # Show backup information
    echo "Backup Information:"
    echo "=================="
    backup_info "$backup_file" --no-header
    echo
    
    # Confirm restoration
    log_warning "⚠️  This will replace your current LAM configuration!"
    if [[ -d "$CONFIG_DIR" ]]; then
        log_warning "   Your current profiles and settings will be lost."
    fi
    echo
    echo -n "Are you sure you want to restore this backup? (y/N): "
    local confirm
    if ! read -r confirm || [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "Restore cancelled."
        return 0
    fi
    
    log_info "Restoring backup..."
    
    # Backup current configuration if it exists
    if [[ -d "$CONFIG_DIR" ]]; then
        local current_backup="$CONFIG_DIR.backup-before-restore-$(date +%s)"
        if cp -r "$CONFIG_DIR" "$current_backup"; then
            log_info "Current configuration backed up to: $current_backup"
        fi
    fi
    
    # Create temporary directory for extraction
    local temp_dir
    if ! temp_dir=$(mktemp -d); then
        log_error "Failed to create temporary directory"
        return 1
    fi
    TEMP_DIRS+=("$temp_dir")
    
    # Extract backup
    if ! tar -xzf "$backup_path" -C "$temp_dir" 2>/dev/null; then
        log_error "Failed to extract backup archive"
        return 1
    fi
    
    # Remove existing configuration
    if [[ -d "$CONFIG_DIR" ]]; then
        rm -rf "$CONFIG_DIR"
    fi
    
    # Restore configuration
    if [[ -d "$temp_dir/lam-config" ]]; then
        # New format with metadata
        cp -r "$temp_dir/lam-config" "$CONFIG_DIR"
        # Remove metadata file from restored config
        rm -f "$CONFIG_DIR/backup-metadata.json"
    else
        # Old format - try to find lam directory
        local lam_dir
        lam_dir=$(find "$temp_dir" -name "lam" -type d | head -1)
        if [[ -n "$lam_dir" ]]; then
            cp -r "$lam_dir" "$CONFIG_DIR"
        else
            log_error "Invalid backup format"
            return 1
        fi
    fi
    
    # Set proper permissions
    chmod 700 "$CONFIG_DIR"
    find "$CONFIG_DIR" -type f -exec chmod 600 {} \;
    
    log_success "Backup restored successfully!"
    echo
    log_info "Your LAM configuration has been restored from: $backup_file"
    log_info "You may need to re-authenticate to access your profiles."
}

# Delete a backup
backup_delete() {
    local backup_file="$1"
    
    if [[ -z "$backup_file" ]]; then
        log_error "Backup filename is required"
        echo "Usage: lam backup delete <backup_filename>"
        echo
        log_info "Available backups:"
        backup_list
        return 1
    fi
    
    local backup_dir="$HOME/.lam-backups"
    local backup_path="$backup_dir/$backup_file"
    
    if [[ ! -f "$backup_path" ]]; then
        log_error "Backup file not found: $backup_file"
        echo
        log_info "Available backups:"
        backup_list
        return 1
    fi
    
    # Show backup info before deletion
    echo "Backup to delete:"
    echo "================"
    backup_info "$backup_file" --no-header
    echo
    
    log_warning "⚠️  This action cannot be undone!"
    echo -n "Are you sure you want to delete this backup? (y/N): "
    local confirm
    if ! read -r confirm || [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "Deletion cancelled."
        return 0
    fi
    
    if rm -f "$backup_path"; then
        log_success "Backup deleted: $backup_file"
    else
        log_error "Failed to delete backup"
        return 1
    fi
}

# Show backup help
backup_help() {
    echo "LAM Backup Management"
    echo "===================="
    echo
    echo "USAGE:"
    echo "    lam backup <action> [arguments]"
    echo
    echo "ACTIONS:"
    echo "    create [name]           Create a new backup (optionally with custom name)"
    echo "    list                    List all available backups"
    echo "    restore <filename>      Restore configuration from backup"
    echo "    delete <filename>       Delete a backup file"
    echo "    info <filename>         Show detailed backup information"
    echo "    help                    Show this help message"
    echo
    echo "EXAMPLES:"
    echo "    lam backup create                    # Create backup with auto-generated name"
    echo "    lam backup create before-update     # Create backup with custom name"
    echo "    lam backup list                     # List all backups"
    echo "    lam backup restore lam-backup-20240730-143022.tar.gz"
    echo "    lam backup info lam-backup-20240730-143022.tar.gz"
    echo "    lam backup delete lam-backup-20240730-143022.tar.gz"
    echo
    echo "BACKUP LOCATION:"
    echo "    $HOME/.lam-backups/"
    echo
    echo "NOTE:"
    echo "    • Backups include all profiles, settings, and session data"
    echo "    • Backups are encrypted with your master password"
    echo "    • Restoring a backup will replace your current configuration"
}