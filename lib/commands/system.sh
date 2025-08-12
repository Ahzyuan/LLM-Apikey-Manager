#!/usr/bin/env bash

# LAM System Related Commands
# Functions: init, status, update, uninstall

# Initialize the tool with enhanced security
cmd_init() {
    # Check if already initialized
    init_config_dir || return 1
    
    if check_initialization 2>/dev/null; then
        # Check if password verification exists in database
        log_info "LAM is already initialized! Now you have triggered a re-initialization."
        log_info "Reinitialization is designed for those who've ${PURPLE}forgotten${NC} or want to ${PURPLE}change${NC} their master password."
        
        echo -en "${RED}Have you forgotten your master password?${NC} (y/N): "
        local forgot_password
        if ! read -r forgot_password; then
            log_error "Failed to read confirmation"
            return 1
        fi

        if [[ $forgot_password == [Yy] ]]; then
            # User forgot master password - require system user authentication
            echo
            log_warning "Given that you have forgotten your master password, all profiles encrypted with it cannot be accessed now."
            log_warning "Therefore, due to security considerations, we will ${RED}delete all of the existing profiles and backups${NC}."
            log_warning "To prevent any form of impersonation, we need to verify your identity before proceeding."
            
            authenticate_user_passwd || return 1
            
            log_success "System user authenticated successfully."

            echo 
            log_warning "⚠️  Now we will ${RED}permanently delete${NC} all existing profiles!"
            echo -en "${RED}Sure to proceed?${NC} (y/N): "
            local del_confirm
            if ! read -r del_confirm; then
                log_error "Failed to read final confirmation"
                return 1
            fi
            
            if [[ "${del_confirm,,}" != "y" ]]; then
                log_info "Operation cancelled."
                return 0
            else
                rm -rf "$CONFIG_DIR" || {
                    log_error "Failed to delete existing profiles"
                    log_info "Please manually delete the profiles directory ($CONFIG_DIR) and try again."
                    return 1
                }

                rm -rf "$BACKUP_DIR" || {
                    log_error "Failed to delete existing backups"
                    log_info "Please manually delete the profiles directory ($BACKUP_DIR) and try again."
                    return 1
                }
                mkdir -p "$CONFIG_DIR"
            fi

            log_success "All profiles and backups deleted. Now you can reset your master password."
            
        else
            # User remembers master password - verify it
            local old_password
            old_password=$(
                get_verified_master_password \
                "${BLUE}Verify your master password to re-init LAM?${NC}: "
            )
            
            if [[ $? -ne 0 ]]; then
                return 1
            fi
            
            log_success "Master password verified successfully."

            echo
            log_info "Now you can set a new master password for your profiles."
            log_info "Changing master password ${PURPLE}won't${NC} affect your existing profiles!"
            log_info "After the change is completed, the old password will be replaced by the new one and become invalid!"
            echo -en "${PURPLE}Do you want to change your master password?${NC} (y/N): "
            local change_confirm
            if ! read -r change_confirm; then
                log_error "Failed to read confirmation"
                return 1
            fi

            if [[ "${change_confirm,,}" == "y" ]]; then
                renew_master_password "$old_password"
                return $?
            else
                echo 
                log_info "Nothing remains to do. Exiting..."
                return 0
            fi
        fi

        echo
        echo '-----------------------------------------'
        echo
    fi
    
    log_info "Initializing LAM (LLM API Manager)"
    echo
    echo "In the following process, you'll need to set up a master password."
    echo "This master password is used to encrypt, decrypt, and access all your API profiles."
    echo
    log_gray "⚠️   The master password can only be set ${PURPLE}ONCE${GRAY} during initialization"
    log_gray "⚠️   Set a strong password (≥ 8 characters) and store it carefully, there's ${PURPLE}no${GRAY} password recovery option"
    log_gray "⚠️   If you forget it, you'll need to ${PURPLE}re-init${GRAY} LAM and it will ${PURPLE}delete all data${NC}."
    echo
    
    local password confirm_password
    if ! password=$(get_master_password "Set master password: " true); then
        return 1
    fi
    
    if ! confirm_password=$(get_master_password "Confirm master password: "); then
        return 1
    fi
    
    if [[ "$password" != "$confirm_password" ]]; then
        log_error "Passwords do not match!"
        return 1
    fi
    
    # Initialize SQLite database
    if ! init_database; then
        return 1
    fi
    
    # Store password verification in database
    if ! init_auth_credential "$password"; then
        return 1
    fi
    
    echo
    log_success "LAM initialized successfully!"
    log_info "💡 You can now add API profiles using: ${PURPLE}lam add <profile_name>${NC}"
}

# Show LAM status and statistics
cmd_status() {
    # Check if LAM is initialized
    if ! check_initialization; then
        log_error "LAM is not initialized"
        return 1
    fi
    
    # Check if session exists and is valid, if not create one
    if [[ ! -f "$SESSION_FILE" ]] || ! is_session_valid; then
        if ! get_verified_master_password >/dev/null; then
            log_error "Authentication failed"
            return 1
        fi
        echo
    fi
    
    echo "LAM Status & Statistics"
    echo "======================"
    echo
    
    # Session info
    echo -e "${BLUE}Session Details${NC}"
    echo "---------------"
    if is_session_valid; then
        log_gray "• Status: Active"
        local session_age
        session_age=$(( $(date +%s) - $(stat -c %Y "$SESSION_FILE" 2>/dev/null || echo 0) ))
        log_gray "• Session Age: ${session_age}s / ${SESSION_TIMEOUT}s"
    else
        log_gray "• Status: Session creation failed"
        log_gray "• Session Age: N/A"
    fi
    echo
    
    # Profile statistics
    local profile_count
    profile_count=$(get_profile_count)
    
    echo -e "${BLUE}Profile Details${NC}"
    echo "---------------"
    
    if [[ "$profile_count" -gt 0 ]]; then
        local current_profile="${LLM_CURRENT_PROFILE:-}"
        local profile_names
        profile_names=$(get_profile_names)
        
        while IFS= read -r profile_name; do
            if [[ -n "$profile_name" ]]; then
                local profile
                profile=$(get_profile "$profile_name")
                
                # Parse environment variable count
                local env_count=0
                
                # Check if env_vars exists and is not empty - simplified approach
                if echo "$profile" | grep -q '"env_vars".*:.*{}'; then
                    # Empty env_vars object
                    env_count=0
                elif echo "$profile" | grep -q '"env_vars".*:.*{.*}'; then
                    # Non-empty env_vars object - count the key-value pairs
                    local env_vars_content
                    env_vars_content=$(echo "$profile" | sed -n 's/.*"env_vars"[[:space:]]*:[[:space:]]*{\([^}]*\)}.*/\1/p')
                    
                    if [[ -n "$env_vars_content" && "$env_vars_content" != "" ]]; then
                        # Count the number of key-value pairs by counting commas + 1
                        env_count=$(echo "$env_vars_content" | grep -o ',' | wc -l)
                        env_count=$((env_count + 1))
                    fi
                fi
                
                # Parse last used
                local last_used
                last_used=$(echo "$profile" | grep -o '"last_used"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"last_used"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo "Never")
                if [[ "$last_used" == "null" || -z "$last_used" ]]; then
                    last_used="Never"
                fi
                
                # Check if this is the active profile
                if [[ "$profile_name" == "$current_profile" ]]; then
                    echo -e "• ${GREEN}$profile_name (active)${NC}: $env_count env vars, last used: $last_used"
                else
                    log_gray "• $profile_name: $env_count env vars, last used: $last_used"
                fi
            fi
        done <<< "$profile_names"
    else
        echo "No profiles configured yet."
        echo "Use 'lam add <profile_name>' to add a profile."
    fi
    echo 
}

# Update LAM with enhanced security
cmd_update() {
    log_info "Checking for LAM updates..."
    
    # Check if we have curl available
    if ! command -v curl &> /dev/null; then
        log_error "curl is required for automatic updates"
        log_info "Please install it: sudo apt-get install curl"
        echo
        log_info "Alternative: Manual update process"
        show_manual_update_instructions
        return 1
    fi
    
    # Create temporary directory for update
    local temp_dir
    if ! temp_dir=$(mktemp -d); then
        log_error "Failed to create temporary directory"
        return 1
    fi
    TEMP_DIRS+=("$temp_dir")
    
    log_info "Downloading latest version..."
    
    # Download the latest version from GitHub
    if curl -sL "https://raw.githubusercontent.com/Ahzyuan/LLM-Apikey-Manager/lam" -o "$temp_dir/lam"; then
        # Verify the downloaded file
        if [[ -f "$temp_dir/lam" ]] && [[ -s "$temp_dir/lam" ]] && head -1 "$temp_dir/lam" | grep -q "#!/usr/bin/env bash"; then
            # Extract version from downloaded file
            local new_version
            new_version=$(grep "^# Version:" "$temp_dir/lam" | head -1 | sed 's/.*Version: //' | sed 's/ .*//')
            
            # Get current version
            local current_version
            current_version=$(grep "^# Version:" "$0" | head -1 | sed 's/.*Version: //' | sed 's/ .*//')
            
            log_info "Current version: $current_version"
            log_info "Latest version: $new_version"
            
            # Check if update is needed
            if [[ "$current_version" == "$new_version" ]]; then
                log_info "You already have the latest version!"
                return 0
            fi
            
            # Find current script location
            local current_script
            current_script=$(readlink -f "$0")
            
            # Backup current version
            if ! cp "$current_script" "$current_script.backup"; then
                log_error "Failed to backup current version"
                return 1
            fi
            log_info "Backed up current version to: $current_script.backup"
            
            # Replace with new version
            if ! cp "$temp_dir/lam" "$current_script"; then
                log_error "Failed to install new version"
                # Restore backup
                cp "$current_script.backup" "$current_script"
                return 1
            fi
            
            # Set executable permissions
            chmod +x "$current_script"
            
            log_success "LAM updated successfully!"
            log_info "Updated from $current_version to $new_version"
            log_info "Restart your terminal or run 'hash -r' to use the new version"
            
        else
            log_error "Downloaded file appears to be corrupted"
            show_manual_update_instructions
            return 1
        fi
    else
        log_error "Failed to download update from GitHub"
        log_info "This might be due to network restrictions or GitHub access issues"
        echo
        show_manual_update_instructions
        return 1
    fi
}

# Show manual update instructions
show_manual_update_instructions() {
    log_info "Manual Update Process:"
    echo "====================="
    echo
    log_info "1. Download LAM source code from GitHub:"
    log_gray "   • Visit: https://github.com/Ahzyuan/LLM-Apikey-Manager"
    log_gray "   • Click 'Code' → 'Download ZIP' OR"
    log_gray "   • Clone: git clone https://github.com/Ahzyuan/LLM-Apikey-Manager.git"
    echo
    log_info "2. Extract and navigate to the project directory:"
    log_gray "   • unzip lam-main.zip && cd lam-main  OR"
    log_gray "   • cd lam"
    echo
    log_info "3. Run the manual update script:"
    log_gray "   • ./version_update.sh"
    echo
    log_gray "The version_update.sh script will:"
    log_gray "• Find your current LAM installation"
    log_gray "• Backup the current version"
    log_gray "• Install the new version"
    log_gray "• Verify the installation"
}

# Uninstall LAM with complete cleanup
cmd_uninstall() {
    # Verify master password for this sensitive operation
    if check_initialization 2>/dev/null; then
        log_info "Please verify your master password before uninstalling:"
        if ! get_verified_master_password >/dev/null; then
            log_error "Authentication failed - cannot uninstall without password verification"
            return 1
        fi
        echo
    fi
    
    log_warning "This will completely remove LAM from your system!"
    echo
    echo "The following will be removed:"
    echo "=============================="
    
    # Find installation locations
    local current_script
    current_script=$(readlink -f "$0")
    local script_dir
    script_dir=$(dirname "$current_script")
    
    # Determine installation type and paths
    local wrapper_script=""
    local lib_dir=""
    
    # Check if this is a wrapper script or main executable
    if [[ "$current_script" == *"/bin/lam" ]]; then
        # This is the wrapper script
        wrapper_script="$current_script"
        # Find the actual installation directory
        if [[ "$current_script" == "/usr/local/bin/lam" ]]; then
            lib_dir="/usr/local/share/lam"
        elif [[ "$current_script" == "$HOME/.local/bin/lam" ]]; then
            lib_dir="$HOME/.local/share/lam"
        fi
    else
        # This is the main executable, find wrapper
        if [[ "$script_dir" == "/usr/local/share/lam" ]]; then
            wrapper_script="/usr/local/bin/lam"
            lib_dir="/usr/local/share/lam"
        elif [[ "$script_dir" == "$HOME/.local/share/lam" ]]; then
            wrapper_script="$HOME/.local/bin/lam"
            lib_dir="$HOME/.local/share/lam"
        else
            # Fallback: try to find wrapper
            for potential_wrapper in "/usr/local/bin/lam" "$HOME/.local/bin/lam"; do
                if [[ -f "$potential_wrapper" ]]; then
                    wrapper_script="$potential_wrapper"
                    break
                fi
            done
            lib_dir="$script_dir"
        fi
    fi
    
    # Show what will be removed
    if [[ -f "$wrapper_script" ]]; then
        echo "• LAM wrapper script: $wrapper_script"
        echo
    fi
    
    if [[ -d "$lib_dir" ]]; then
        echo "• LAM installation directory: $lib_dir"
        log_gray "  ├─ Main executable: $lib_dir/lam"
        log_gray "  ├─ VERSION file: $lib_dir/VERSION"
        log_gray "  └─ Library modules: $lib_dir/lib/"
        echo
    fi
    
    # Check for user configuration
    if [[ -d "$CONFIG_DIR" ]]; then
        echo "• Configuration directory: $CONFIG_DIR"
        log_gray "  (contains encrypted API keys and profiles)"
        echo
    fi
    
    # Check for LAM backup directory
    local backup_dir="$HOME/.lam-backups"
    if [[ -d "$backup_dir" ]]; then
        echo "• LAM backup directory: $backup_dir"
        local backup_count
        backup_count=$(find "$backup_dir" -name "*.tar.gz" 2>/dev/null | wc -l)
        log_gray "  (contains $backup_count configuration backup(s))"
        echo
    fi
    
    # Check for backup files
    local backup_files=()
    for potential_backup in "$wrapper_script.backup" "$lib_dir/lam.backup" "$current_script.backup"; do
        if [[ -f "$potential_backup" ]]; then
            backup_files+=("$potential_backup")
        fi
    done
    
    if [[ ${#backup_files[@]} -gt 0 ]]; then
        echo "• Installation backup files:"
        for backup in "${backup_files[@]}"; do
            echo "  • $backup"
        done
        echo
    fi
    
    echo
    log_warning "⚠️  This action cannot be undone!"
    log_gray "   Your encrypted API keys and profiles will be permanently deleted."
    echo
    
    echo -en "${RED}Are you sure you want to uninstall LAM?${NC} (type 'yes' to confirm): "
    local confirmation
    if ! read -r confirmation; then
        log_error "Failed to read confirmation"
        return 1
    fi
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Uninstallation cancelled."
        return 0
    fi
    
    echo
    log_info "Uninstalling LAM..."
    
    # Remove configuration directory (includes session files) FIRST
    if [[ -d "$CONFIG_DIR" ]]; then
        if rm -rf "$CONFIG_DIR"; then
            log_success "Removed configuration directory and all session data"
        else
            log_error "Failed to remove configuration directory"
            log_info "You can manually delete this directory by running 'rm -rf $CONFIG_DIR'."
            echo
        fi
    fi
    
    # Remove LAM backup directory
    if [[ -d "$backup_dir" ]]; then
        if rm -rf "$backup_dir"; then
            log_success "Removed LAM backup directory and all backups"
        else
            log_error "Failed to remove LAM backup directory"
            log_info "You can manually delete this directory by running 'rm -rf $backup_dir'."
            echo
        fi
    fi
    
    # Remove installation backup files
    for backup in "${backup_files[@]}"; do
        if [[ -f "$backup" ]]; then
            if rm -f "$backup"; then
                log_success "Removed installation backup file: $backup"
            else
                log_warning "Failed to remove installation backup file: $backup"
                log_info "You can manually delete this file by running 'rm -f $backup'."
                echo
            fi
        fi
    done
    
    # Remove LAM installation directory
    if [[ -d "$lib_dir" && "$lib_dir" != "/" && "$lib_dir" != "$HOME" ]]; then
        if rm -rf "$lib_dir"; then
            log_success "Removed LAM installation directory: $lib_dir"
        else
            log_error "Failed to remove LAM installation directory: $lib_dir"
            log_info "You can manually delete this directory by running 'rm -rf $lib_dir'."
        fi
    fi
    
    # Remove wrapper script
    if [[ -f "$wrapper_script" && "$wrapper_script" != "$current_script" ]]; then
        if rm -f "$wrapper_script"; then
            log_success "Removed LAM wrapper script: $wrapper_script"
        else
            log_error "Failed to remove LAM wrapper script: $wrapper_script"
            log_info "You can manually delete this file by running 'rm -f $wrapper_script'."
            echo
        fi
    fi
    
    echo
    log_success "LAM has been completely removed from your system! Goodbye! 👋"
    
    # If we're running the wrapper script, just exit
    # If we're running the main executable, use self-deletion
    if [[ "$current_script" == "$wrapper_script" ]]; then
        exit 0
    else
        # Create a self-deleting script to remove the current executable
        local cleanup_script="/tmp/lam_cleanup_$$"
        cat > "$cleanup_script" << 'EOF'
#!/usr/bin/env bash
sleep 1  # Wait for parent script to exit
if [[ -f "$1" ]]; then
    rm -f "$1"
fi
rm -f "$0"  # Remove this cleanup script
EOF
        chmod +x "$cleanup_script"
        
        # Start cleanup script in background and exit immediately
        "$cleanup_script" "$current_script" &
        exit 0
    fi
}