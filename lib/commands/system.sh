#!/usr/bin/env bash

# LAM System Related Commands
# Functions: init, status, update, uninstall

# Initialize or reset LAM with master password setup
# Arguments:
#   None (prompts user for password input)
# Returns:
#   0 on success, 1 on failure
# Globals:
#   Uses init_config_dir, init_database, and authentication functions
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

                # shellcheck disable=SC2153
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
            
            if ! old_password=$(
                get_verified_master_password \
                "${BLUE}Verify your master password to re-init LAM?${NC}: "
            ); then
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
    
    log_info "Initializing LAM (LLM API-key Manager)"
    echo
    echo "In the following process, you'll need to set up a master password."
    echo "This master password is used to encrypt, decrypt, and access all your API profiles."
    echo
    log_gray "⚠️   The master password can only be set ${PURPLE}ONCE${GRAY} during initialization"
    log_gray "⚠️   Set a strong password (8 ~ 256 characters) and store it carefully, there's ${PURPLE}no${GRAY} password recovery option"
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

# Display LAM status, statistics, and system information
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
# Globals:
#   Uses various status and metadata functions
cmd_status() {    
    # Check if session exists and is valid, if not create one
    if ! is_session_valid; then
        local master_password
        if master_password=$(get_verified_master_password); then
            create_session "$master_password" || exit 1
        else
            return 1
        fi
    fi
    echo
    
    # Session info
    local session_age
    session_age=$(( $(date +%s) - $(stat -c %Y "$SESSION_FILE" 2>/dev/null || echo 0) ))
    echo -e "${BLUE}✦ Session Age${NC}: ${GRAY}${session_age}s / ${SESSION_TIMEOUT}s${NC}"
    echo 
    
    # Profile statistics
    local profile_count
    profile_count=$(get_profile_count)
    
    echo -e "${BLUE}✦ Profile Details${NC}"
    
    if [[ "$profile_count" -gt 0 ]]; then
        local current_profile="${LLM_CURRENT_PROFILE:-}"
        local profile_names
        profile_names=$(get_profile_names)
        
        while IFS= read -r profile_name; do
            if [[ -n "$profile_name" ]]; then
                local profile env_count last_used
                profile=$(get_profile "$profile_name")

                env_count=$(echo "$profile" | jq -r '.env_vars | length' 2>/dev/null || echo "0")
                last_used=$(echo "$profile" | jq -r '.last_used // "Never"' 2>/dev/null || echo "Never")
                
                if [[ "$profile_name" == "$current_profile" ]]; then
                    echo -e "  └─ ${GREEN}$profile_name (active)${NC}: $env_count env vars, last used: $last_used"
                else
                    log_gray "  └─ $profile_name: $env_count env vars, last used: $last_used"
                fi
            fi
        done <<< "$profile_names"
    else
        log_gray "No profiles configured yet."
        log_gray "Use ${PURPLE}'lam add <profile_name>'${GRAY} to add a profile."
    fi
    echo 
}

# Update LAM to latest version with enhanced security
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
# Globals:
#   SCRIPT_DIR: Installation directory for update operations
cmd_update() {
    log_info "Checking for LAM updates..."
    echo
    
    # Set up trap for update failure - prompt manual update
    trap 'echo
          manual_update_instructions
          echo
          log_info "If you continue to experience issues, please report them at: ${PURPLE}https://github.com/Ahzyuan/LLM-Apikey-Manager/issues${NC}"
    ' EXIT
    
    check_dependencies
    
    # Determine current installation type and paths
    local current_script script_dir wrapper_script lib_dir 
    local is_system_install=false
    current_script=$(readlink -f "$0")
    script_dir=$(dirname "$current_script")
    
    if [[ "$current_script" == *"/bin/lam" ]]; then
        # This is the wrapper script
        wrapper_script="$current_script"
        # Find the actual installation directory
        if [[ "$current_script" == "/usr/local/bin/lam" ]]; then
            lib_dir="/usr/local/share/lam"
            is_system_install=true
        elif [[ "$current_script" == "$HOME/.local/bin/lam" ]]; then
            lib_dir="$HOME/.local/share/lam"
        fi
    else
        # This is the main executable, find wrapper
        if [[ "$script_dir" == "/usr/local/share/lam" ]]; then
            wrapper_script="/usr/local/bin/lam"
            lib_dir="/usr/local/share/lam"
            is_system_install=true
        elif [[ "$script_dir" == "$HOME/.local/share/lam" ]]; then
            wrapper_script="$HOME/.local/bin/lam"
            lib_dir="$HOME/.local/share/lam"
        else
            log_error "Found LAM installed in unsupported directory: ${PURPLE}$script_dir${NC}"
            log_error "Operation aborted."
            trap - EXIT
            return 1
        fi
    fi

    # Check permissions for system-wide installation
    if $is_system_install && [[ $EUID -ne 0 ]]; then
        log_warning "⚠️  Permission Issue Detected!"
        log_info "LAM is installed system-wide, but you're running update without ${PURPLE}sudo${NC}."
        log_info "Please use ${PURPLE}'sudo lam update'${NC} to update LAM."
        trap - EXIT
        return 1
    fi
    
    # Create temporary directory for update
    local temp_dir
    if ! temp_dir=$(mktemp -d); then
        log_error "Failed to create temporary directory"
        log_error "Please ensure you have permission to create directories in /tmp"
        trap - EXIT
        return 1
    fi
    TEMP_DIRS+=("$temp_dir")
        
    # Download the latest release tarball from GitHub
    local github_url="https://github.com/Ahzyuan/LLM-Apikey-Manager/archive/refs/heads/master.tar.gz"
    if ! curl --max-time 5 -sL "$github_url" -o "$temp_dir/lam-latest.tar.gz"; then
        log_error "Failed to download update from GitHub"
        log_error "This might be due to network restrictions or GitHub access issues"
        echo
        log_info "Please try again later or manually update by following these instructions:"
        exit 1
    fi
    
    # Extract the downloaded archive
    if ! tar -xzf "$temp_dir/lam-latest.tar.gz" -C "$temp_dir" 2>/dev/null; then
        log_error "Failed to extract update package"
        log_error "Your system might not have enough disk space or the downloaded archive is corrupted"
        echo
        log_info "Please try again later or manually update by following these instructions:"
        exit 1
    fi
    
    local extracted_dir
    extracted_dir=$(find "$temp_dir" -name "LLM-Apikey-Manager-*" -type d | head -1)
    if [[ ! -d "$extracted_dir" ]]; then
        log_error "Could not find extracted LAM directory"
        echo
        log_info "Please try again later or manually update by following these instructions:"
        exit 1
    fi
    
    # Validate the downloaded version
    if [[ ! -f "$extracted_dir/lam" ]] || [[ ! -d "$extracted_dir/lib" ]]; then
        log_error "Downloaded package appears to be incomplete or corrupted"
        log_error "Missing required files: lam executable or lib directory"
        echo
        log_info "Please try again later or manually update by following these instructions:"
        exit 1
    fi
        
    local current_version new_version
    current_version=$(get_version_info | cut -d'|' -f1)
    if [[ -f "$extracted_dir/VERSION" ]]; then
        new_version=$(head -1 "$extracted_dir/VERSION" | tr -d '[:space:]')
    else
        new_version="unknown"
    fi
    
    log_info "Current version: ${PURPLE}$current_version${NC}"
    log_info "Latest version: ${PURPLE}$new_version${NC}"
    
    if [[ "$current_version" == "$new_version" && "$current_version" != "unknown" ]]; then
        log_info "You already have the latest version!"
        trap - EXIT
        return 0
    fi
    
    # Backup current installation
    if [[ -f "$lib_dir/lam" ]]; then
        if ! cp "$lib_dir/lam" "$lib_dir/lam.backup"; then
            log_error "Failed to backup current LAM executable"
            log_error "Please ensure you have write permissions to ${PURPLE}$lib_dir${NC}"
            trap - EXIT
            return 1
        fi
        log_info "Backed up current executable to: ${PURPLE}$lib_dir/lam.backup${NC}"
    fi
    
    if [[ -n "$wrapper_script" && -f "$wrapper_script" ]]; then
        if ! cp "$wrapper_script" "$wrapper_script.backup"; then
            log_error "Failed to backup wrapper script"
            log_error "Please ensure you have permission to write to: ${PURPLE}$(dirname "$wrapper_script")${NC}"
            trap - EXIT
            return 1
        fi
        log_info "Backed up wrapper script to: ${PURPLE}$wrapper_script.backup${NC}"
    fi
    
    # Install new version
    echo
    log_info "Updating LAM..."
    
    if ! cp "$extracted_dir/lam" "$lib_dir/lam"; then
        log_error "Failed to install new LAM executable"
        # Restore backup
        [[ -f "$lib_dir/lam.backup" ]] && cp "$lib_dir/lam.backup" "$lib_dir/lam"
        echo
        log_info "Please try again later or manually update by following these instructions:"
        exit 1
    fi
    
    if ! cp -r "$extracted_dir/lib"/* "$lib_dir/lib/"; then
        log_error "Failed to install new library modules"
        # Restore backup
        [[ -f "$lib_dir/lam.backup" ]] && cp "$lib_dir/lam.backup" "$lib_dir/lam"
        echo
        log_info "Please try again later or manually update by following these instructions:"
        exit 1
    fi
    
    if [[ -f "$extracted_dir/VERSION" ]]; then
        cp "$extracted_dir/VERSION" "$lib_dir/VERSION" 2>/dev/null || true
    fi
    
    chmod +x "$lib_dir/lam"
    find "$lib_dir/lib" -name "*.sh" -type f -exec chmod +x {} \;
    
    if [[ -n "$wrapper_script" && -f "$wrapper_script" ]]; then
        cat > "$wrapper_script" << EOF
#!/usr/bin/env bash
# LAM (LLM API-key Manager) - Wrapper Script
# This script launches the main LAM executable

exec "$lib_dir/lam" "\$@"
EOF
        chmod +x "$wrapper_script"
    fi
    
    echo
    log_success "LAM updated successfully!"
    log_success "Updated from ${PURPLE}$current_version${NC} to ${PURPLE}$new_version${NC}"
    log_success "All modules and dependencies have been updated"
    echo
    log_info "💡 ${BLUE}Next Steps${NC}:"
    log_gray "• Restart your terminal or run ${PURPLE}'hash -r'${NC} to refresh the command cache"
    log_gray "• Run ${PURPLE}'lam version'${NC} to verify the new version"
    log_gray "• Your profiles and configuration remain unchanged"
    
    # Clear trap on successful completion
    trap - EXIT
}

# Display manual update instructions when automatic update fails
# Arguments:
#   None
# Returns:
#   Always returns 0
# Globals:
#   None
manual_update_instructions() {
    echo -e "${BLUE}1. Download LAM source code from GitHub:${NC}"
    log_gray "   • Visit: ${PURPLE}https://github.com/Ahzyuan/LLM-Apikey-Manager${NC}"
    log_gray "   • Click ${PURPLE}'Code' → 'Download ZIP'${NC} OR"
    log_gray "   • Clone: ${PURPLE}git clone https://github.com/Ahzyuan/LLM-Apikey-Manager.git${NC}"
    echo
    echo -e "${BLUE}2. Extract and navigate to the project directory:${NC}"
    log_gray "   • ${PURPLE}unzip LLM-Apikey-Manager-main.zip && cd LLM-Apikey-Manager-main${NC}  OR"
    log_gray "   • ${PURPLE}cd LLM-Apikey-Manager${NC}"
    echo
    echo -e "${BLUE}3. Run the installation script:${NC}"
    log_gray "   • System-wide installation: ${PURPLE}sudo bash install.sh${NC}"
    log_gray "   • User-local installation: ${PURPLE}bash install.sh${NC}"
    echo
    echo -e "${BLUE}4. Verify the installation:${NC}"
    log_gray "   • Check LAM version: ${PURPLE}lam version${NC}"
    log_gray "   • Your existing profiles and configuration will be preserved"
}

# Completely uninstall LAM with comprehensive cleanup
# Arguments:
#   None
# Returns:
#   0 on success, 1 on failure
# Globals:
#   CONFIG_DIR, BACKUP_DIR, SCRIPT_DIR: Directories for cleanup
cmd_uninstall() {
    if check_initialization 2>/dev/null; then
        local master_password
        if ! master_password=$(get_verified_master_password); then
            return 1
        fi
    fi
    
    # Find installation locations
    local current_script script_dir
    current_script=$(readlink -f "$0")
    script_dir=$(dirname "$current_script")
    
    # Determine installation type and paths
    local wrapper_script=""
    local lib_dir=""
    local is_system_install=false
    
    # Check if this is a wrapper script or main executable
    if [[ "$current_script" == *"/bin/lam" ]]; then
        # This is the wrapper script
        wrapper_script="$current_script"
        # Find the actual installation directory
        if [[ "$current_script" == "/usr/local/bin/lam" ]]; then
            lib_dir="/usr/local/share/lam"
            is_system_install=true
        elif [[ "$current_script" == "$HOME/.local/bin/lam" ]]; then
            lib_dir="$HOME/.local/share/lam"
        fi
    else
        # This is the main executable, find wrapper
        if [[ "$script_dir" == "/usr/local/share/lam" ]]; then
            wrapper_script="/usr/local/bin/lam"
            lib_dir="/usr/local/share/lam"
            is_system_install=true
        elif [[ "$script_dir" == "$HOME/.local/share/lam" ]]; then
            wrapper_script="$HOME/.local/bin/lam"
            lib_dir="$HOME/.local/share/lam"
        else
            log_error "Unsupported installation directory: ${PURPLE}$script_dir${NC}"
            log_error "Uninstall aborted."
            exit 1
        fi
    fi
    
    # Early sudo detection for system-wide installations
    if [[ $is_system_install == true && $EUID -ne 0 ]]; then
        echo
        log_warning "LAM was installed system-wide and requires ${PURPLE}'sudo'${NC} privileges to remove."
        log_warning "Please use ${PURPLE}'sudo lam uninstall'${NC} to uninstall LAM."
        exit 1
    fi
    
    # Show what will be removed
    log_warning "This will completely remove LAM from your system!"
    echo
    echo "The following will be removed:"
    echo "=============================="
    
    if [[ -f "$wrapper_script" ]]; then
        echo -e "• ${PURPLE}LAM wrapper script${NC}: $wrapper_script"
        echo
    fi
    
    if [[ -d "$lib_dir" ]]; then
        echo -e "• ${PURPLE}LAM installation directory${NC}: $lib_dir"
        log_gray "  ├─ Main executable: $lib_dir/lam"
        log_gray "  ├─ VERSION file: $lib_dir/VERSION"
        log_gray "  └─ Library modules: $lib_dir/lib/"
        echo
    fi
    
    if [[ -d "$CONFIG_DIR" ]]; then
        echo -e "• ${PURPLE}Configuration directory${NC}: $CONFIG_DIR"
        log_gray "  (contains all of your encrypted profiles)"
        echo
    fi
    
    local backup_dir="$HOME/.lam-backups"
    if [[ -d "$backup_dir" ]]; then
        local backup_count
        backup_count=$(find "$backup_dir" -name "*.tar.gz" 2>/dev/null | wc -l)
        
        echo -e "• ${PURPLE}LAM backup directory${NC}: $backup_dir"
        log_gray "  (contains $backup_count configuration backup(s))"
        echo
    fi
    
    local backup_files=()
    for potential_backup in "$wrapper_script.backup" "$lib_dir/lam.backup" "$current_script.backup"; do
        if [[ -f "$potential_backup" ]]; then
            backup_files+=("$potential_backup")
        fi
    done
    
    if [[ ${#backup_files[@]} -gt 0 ]]; then
        echo -e "• ${PURPLE}Installation backup files${NC}:"
        for backup in "${backup_files[@]}"; do
            log_gray "  └─ $backup"
        done
        echo
    fi
    
    log_warning "⚠️  This action cannot be undone!"
    log_warning "All of your encrypted profiles and backups will be permanently deleted."
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
    local need_manual_cleanup=false cmd_prefix=""
    if $is_system_install; then
        cmd_prefix="sudo "
    fi
    
    # Remove configuration directory (includes session files) FIRST
    if [[ -d "$CONFIG_DIR" ]]; then
        if ! rm -rf "$CONFIG_DIR"; then
            need_manual_cleanup=true
            log_error "Failed to remove configuration directory."
            log_info "You can manually delete this directory by running ${PURPLE}'${cmd_prefix}rm -rf $CONFIG_DIR'${NC}."
        fi
    fi
    
    # Remove LAM backup directory
    if [[ -d "$backup_dir" ]]; then
        if ! rm -rf "$backup_dir"; then
            need_manual_cleanup=true
            log_error "Failed to remove LAM backup directory."
            log_info "You can manually delete this directory by running ${PURPLE}'${cmd_prefix}rm -rf $backup_dir'${NC}."
        fi
    fi
    
    # Remove installation backup files
    for backup in "${backup_files[@]}"; do
        if ! rm -f "$backup" 2>/dev/null; then
            need_manual_cleanup=true
            log_error "Failed to remove installation backup file: ${PURPLE}$backup${NC}."
            log_info "You can manually delete this file by running ${PURPLE}'${cmd_prefix}rm -f $backup'${NC}."
        fi
    done
    
    # Remove LAM installation directory
    if [[ -d "$lib_dir" && "$lib_dir" != "/" && "$lib_dir" != "$HOME" ]]; then
        if ! rm -rf "$lib_dir" 2>/dev/null; then
            need_manual_cleanup=true
            log_error "Failed to remove LAM installation directory: ${PURPLE}$lib_dir${NC}."
            log_info "You can manually delete this directory by running ${PURPLE}'${cmd_prefix}rm -rf $lib_dir'${NC}."
        fi
    fi
    
    # Remove wrapper script
    if [[ -f "$wrapper_script" && "$wrapper_script" != "$current_script" ]]; then
        if ! rm -f "$wrapper_script" 2>/dev/null; then
            need_manual_cleanup=true
            log_error "Failed to remove LAM wrapper script: ${PURPLE}$wrapper_script${NC}."
            log_info "You can manually delete this file by running ${PURPLE}'${cmd_prefix}rm -f $wrapper_script'${NC}."
        fi
    fi
    
    if $need_manual_cleanup; then
        log_success "LAM has been removed, however some files cannot be deleted because of privileges. Please manually delete them 👆."
    else
        log_success "LAM has been completely removed from your system! Goodbye! 👋"
    fi
    
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