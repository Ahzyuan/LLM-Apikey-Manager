#!/bin/bash

# LAM Core Commands Module
# Profile management: init, add, list, show, use, edit, delete

# Initialize the tool with enhanced security
cmd_init() {
    log_info "Initializing LAM (LLM API Manager)..."
    
    if ! init_config_dir; then
        return 1
    fi
    
    if [[ -f "$CONFIG_FILE" ]]; then
        log_warning "LAM is already initialized!"
        echo -n "Do you want to reset and create a new configuration? (y/N): "
        local confirm
        if ! read -r confirm; then
            log_error "Failed to read confirmation"
            return 1
        fi
        
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            log_info "Initialization cancelled."
            return 0
        fi
        
        log_warning "This will delete all existing profiles!"
        echo -n "Are you absolutely sure? (type 'yes' to confirm): "
        if ! read -r confirm; then
            log_error "Failed to read confirmation"
            return 1
        fi
        
        if [[ "$confirm" != "yes" ]]; then
            log_info "Initialization cancelled."
            return 0
        fi
    fi
    
    # Get master password
    local password confirm_password
    
    echo
    log_info "Please create a master password to encrypt your API keys."
    log_gray "This password will be required to access your stored credentials."
    echo
    
    if ! password=$(get_master_password "Create master password: "); then
        return 1
    fi
    
    if ! confirm_password=$(get_master_password "Confirm master password: "); then
        return 1
    fi
    
    if [[ "$password" != "$confirm_password" ]]; then
        log_error "Passwords do not match!"
        return 1
    fi
    
    # Create initial empty configuration
    local initial_config='{"profiles":{},"metadata":{"created":"'$(date -Iseconds)'","version":"'$(get_version_info | cut -d'|' -f1)'"}}'
    
    if ! save_session_config "$initial_config" "$password"; then
        log_error "Failed to save initial configuration"
        return 1
    fi
    
    log_success "LAM initialized successfully!"
    echo
    log_info "You can now add API profiles using: lam add <profile_name>"
}

# Add new API profile with enhanced validation
cmd_add() {
    local name="$1"
    
    if [[ -z "$name" ]]; then
        log_error "Profile name is required!"
        echo "Usage: lam add <profile_name>"
        return 1
    fi
    
    # Validate profile name
    if ! validate_env_key "$name"; then
        log_error "Invalid profile name format"
        return 1
    fi
    
    local config
    if ! config=$(get_session_config); then
        return 1
    fi
    
    # Check if profile already exists
    local existing_profile
    existing_profile=$(echo "$config" | jq -r ".profiles[\"$name\"]" 2>/dev/null)
    
    if [[ "$existing_profile" != "null" ]]; then
        log_warning "Profile '$name' already exists!"
        echo -en "${YELLOW}Do you want to overwrite it? (y/N): ${NC}"
        local confirm
        if ! read -r confirm; then
            log_error "Failed to read confirmation"
            return 1
        fi
        
        if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
            log_info "Operation cancelled."
            return 0
        fi
    fi
    
    log_info "Adding new API profile: $name"
    echo
    
    # Collect Model Name (required)
    local model_name
    while true; do
        echo -en "${BLUE}Model Name${NC} (required, e.g., gpt-4, claude-3-sonnet): "
        if ! read -r model_name; then
            log_error "Failed to read model name"
            return 1
        fi
        
        model_name=$(sanitize_input "$model_name")
        if [[ -z "$model_name" ]]; then
            log_error "Model name is required!"
            continue
        fi
        
        if [[ ${#model_name} -gt 100 ]]; then
            log_error "Model name too long (max 100 characters)"
            continue
        fi
        
        break
    done
    log_success "Model: $model_name"
    echo
    
    # Initialize empty env_vars object
    local env_vars='{}'
    
    # Collect API Key
    echo -en "${BLUE}API Key${NC} (e.g., OPENAI_API_KEY=sk-123): "
    local api_key_input
    if ! read -r api_key_input; then
        log_error "Failed to read API key"
        return 1
    fi
    
    # Validate and parse API key input
    api_key_input=$(sanitize_input "$api_key_input")
    if [[ ! "$api_key_input" =~ ^[A-Za-z_][A-Za-z0-9_]*=.+$ ]]; then
        log_error "Invalid format! Use KEY=VALUE (e.g., OPENAI_API_KEY=sk-123...)"
        return 1
    fi
    
    local api_key_name="${api_key_input%%=*}"
    local api_key_value="${api_key_input#*=}"
    
    if ! validate_env_key "$api_key_name" || ! validate_env_value "$api_key_value"; then
        return 1
    fi
    
    env_vars=$(echo "$env_vars" | jq --arg key "$api_key_name" --arg value "$api_key_value" '.[$key] = $value')
    log_success "Added: $api_key_name=***"
    echo
    
    # Collect Base URL (optional)
    echo -en "${BLUE}Base URL${NC} (optional, e.g., OPENAI_BASE_URL=https://api.openai.com/v1): "
    local base_url_input
    if ! read -r base_url_input; then
        log_error "Failed to read base URL"
        return 1
    fi
    
    if [[ -n "$base_url_input" ]]; then
        base_url_input=$(sanitize_input "$base_url_input")
        if [[ ! "$base_url_input" =~ ^[A-Za-z_][A-Za-z0-9_]*=.+$ ]]; then
            log_error "Invalid format! Use KEY=VALUE (e.g., OPENAI_BASE_URL=https://api.openai.com/v1)"
            return 1
        fi
        
        local base_url_name="${base_url_input%%=*}"
        local base_url_value="${base_url_input#*=}"
        
        if ! validate_env_key "$base_url_name" || ! validate_env_value "$base_url_value"; then
            return 1
        fi
        
        env_vars=$(echo "$env_vars" | jq --arg key "$base_url_name" --arg value "$base_url_value" '.[$key] = $value')
        log_success "Added: $base_url_name=$base_url_value"
    else
        log_info "Base URL: (skipped)"
    fi
    echo
    
    # Collect additional environment variables
    while true; do
        echo -en "${BLUE}Additional ENV${NC} (KEY=VALUE format, or press Enter to finish): "
        local additional_env
        if ! read -r additional_env; then
            log_error "Failed to read additional environment variable"
            return 1
        fi
        
        # If empty, break the loop
        if [[ -z "$additional_env" ]]; then
            log_info "No additional environment variables added."
            break
        fi
        
        additional_env=$(sanitize_input "$additional_env")
        if [[ ! "$additional_env" =~ ^[A-Za-z_][A-Za-z0-9_]*=.+$ ]]; then
            log_error "Invalid format! Use KEY=VALUE"
            continue
        fi
        
        local env_name="${additional_env%%=*}"
        local env_value="${additional_env#*=}"
        
        if ! validate_env_key "$env_name" || ! validate_env_value "$env_value"; then
            continue
        fi
        
        env_vars=$(echo "$env_vars" | jq --arg key "$env_name" --arg value "$env_value" '.[$key] = $value')
        log_success "Added: $env_name"
    done
    echo
    
    # Collect description (optional)
    echo -en "${BLUE}Description${NC} (optional): "
    local description
    if ! read -r description; then
        log_error "Failed to read description"
        return 1
    fi
    
    description=$(sanitize_input "$description")
    if [[ -z "$description" ]]; then
        description="No description provided"
    fi
    log_success "Description: $description"
    echo
    
    # Create profile object
    local profile_data
    profile_data=$(jq -n \
        --argjson env_vars "$env_vars" \
        --arg model_name "$model_name" \
        --arg description "$description" \
        --arg created "$(date -Iseconds)" \
        '{
            env_vars: $env_vars,
            model_name: $model_name,
            description: $description,
            created: $created,
            last_used: null
        }')
    
    # Add profile to config
    config=$(echo "$config" | jq --arg name "$name" --argjson profile "$profile_data" '.profiles[$name] = $profile')
    
    # Save configuration
    local password
    if ! password=$(get_verified_master_password); then
        return 1
    fi
    
    if ! save_session_config "$config" "$password"; then
        log_error "Failed to save configuration"
        return 1
    fi
    
    log_success "Profile '$name' added successfully!"
    echo
    log_info "Environment variables configured:"
    echo "$env_vars" | jq -r 'to_entries[] | "• \(.key)"'
    echo
    log_info "💡 To use this profile, run: lam use $name"
}

# List all profiles with enhanced formatting
cmd_list() {
    local config
    if ! config=$(get_session_config); then
        return 1
    fi
    
    local profiles
    profiles=$(echo "$config" | jq -r '.profiles | keys[]' 2>/dev/null)
    
    if [[ -z "$profiles" ]]; then
        log_info "No profiles configured yet."
        log_info "Use 'lam add <profile_name>' to add a profile."
        return 0
    fi
    
    echo "Available LLM API Profiles:"
    echo "=========================="
    
    while IFS= read -r profile_name; do
        local profile
        profile=$(echo "$config" | jq -r ".profiles[\"$profile_name\"]")
        local env_vars
        env_vars=$(echo "$profile" | jq -r '.env_vars')
        local description
        description=$(echo "$profile" | jq -r '.description // "No description"')
        local last_used
        last_used=$(echo "$profile" | jq -r '.last_used // "Never"')
        local env_keys
        env_keys=$(echo "$env_vars" | jq -r 'keys | join(", ")')
        
        echo
        echo "Name: $profile_name"
        echo "Environment Variables: $env_keys"
        echo "Description: $description"
        echo "Last Used: $last_used"
        echo "---"
    done <<< "$profiles"
}

# Show specific profile with secure masking
cmd_show() {
    local name="$1"
    
    if [[ -z "$name" ]]; then
        log_error "Profile name is required!"
        echo "Usage: lam show <profile_name>"
        return 1
    fi
    
    local config
    if ! config=$(get_session_config); then
        return 1
    fi
    
    local profile
    profile=$(echo "$config" | jq -r ".profiles[\"$name\"]" 2>/dev/null)
    
    if [[ "$profile" == "null" ]]; then
        log_error "Profile '$name' not found!"
        log_info "Available profiles:"
        echo "$config" | jq -r '.profiles | keys[]' | sed 's/^/• /'
        exit 1
    fi
    
    echo -e "${BLUE}Profile Details${NC}"
    echo "===================="
    echo -e "${PURPLE}• Profile Name${NC}: $name"
    
    local model_name
    model_name=$(echo "$profile" | jq -r '.model_name // "Not specified"')
    echo -e "${PURPLE}• Model Name${NC}: $model_name"
    
    local description
    description=$(echo "$profile" | jq -r '.description // "No description"')
    echo -e "${PURPLE}• Description${NC}: $description"
    
    echo
    local created
    created=$(echo "$profile" | jq -r '.created // "Unknown"')
    echo -e "${PURPLE}• Created${NC}: $created"
    
    local last_used
    last_used=$(echo "$profile" | jq -r '.last_used // "Never"')
    echo -e "${PURPLE}• Last Used${NC}: $last_used"
    
    echo 
    # Show environment variables with masked values
    echo -e "${PURPLE}• Environment Variables${NC}:"
    
    local env_vars
    env_vars=$(echo "$profile" | jq -r '.env_vars')
    
    while IFS= read -r key; do
        local value
        value=$(echo "$env_vars" | jq -r ".[\"$key\"]")
        
        # Mask the value for security (show first 4 and last 4 characters)
        local masked_value
        if [[ ${#value} -gt 8 ]]; then
            masked_value="${value:0:4}...${value: -4}"
        else
            masked_value="***"
        fi
        
        echo -e "  └─ ${GREEN}$key${NC} = $masked_value"
    done <<< "$(echo "$env_vars" | jq -r 'keys[]')"
    
    echo 
    echo '------------------------------------'
    log_gray "To use this profile: lam use $name"
    log_gray "To edit this profile: lam edit $name"
}

# Export profile to environment variables
cmd_use() {
    local name="$1"
    
    if [[ -z "$name" ]]; then
        log_error "Profile name is required!"
        echo "Usage: lam use <profile_name>"
        return 1
    fi
        
    local config
    if ! config=$(get_session_config); then
        return 1
    fi
    
    local profile
    profile=$(echo "$config" | jq -r ".profiles[\"$name\"]" 2>/dev/null)
    if [[ "$profile" == "null" ]]; then
        log_error "Profile '$name' not found!" >&2
        log_info "Available profiles:" >&2
        echo "$config" | jq -r '.profiles | keys[]' | sed 's/^/• /' >&2
        exit 1
    fi

    # Check if we're being called within eval (stdout will be captured)
    if [[ -t 1 ]]; then
        log_info "💡 To use profile ${GREEN}'$name'${NC}, run: ${PURPLE}source <(lam use $name)${NC}"
        return 0
    fi
    
    local env_vars
    env_vars=$(echo "$profile" | jq -r '.env_vars')
    local model_name
    model_name=$(echo "$profile" | jq -r '.model_name')
    
    # Update last used timestamp
    config=$(echo "$config" | jq ".profiles[\"$name\"].last_used = \"$(date -Iseconds)\"") || {
        log_error "Failed to update last used timestamp"
        return 1
    }
    
    # Get password for saving
    local password
    if ! password=$(get_verified_master_password); then
        return 1
    fi
    
    if ! save_session_config "$config" "$password"; then
        log_error "Failed to save configuration"
        return 1
    fi
    
    echo "$env_vars" | jq -r 'to_entries[] | "export \(.key)='"'"'\(.value)'"'"'"'
    echo "export LLM_CURRENT_PROFILE='$name'"

    local exported_vars
    exported_vars=$(echo "$env_vars" | jq -r 'keys | join(", ")')
    log_success "Profile ${GREEN}'$name'${NC} activated!"
    log_info "Variables exported: $exported_vars, LLM_CURRENT_PROFILE"
}

# Edit existing configuration with enhanced validation
cmd_edit() {
    local name="$1"
    
    if [[ -z "$name" ]]; then
        log_error "Profile name is required!"
        echo "Usage: lam edit <profile_name>"
        exit 1
    fi
    
    local config
    if ! config=$(get_session_config); then
        exit 1
    fi
    
    local profile
    profile=$(echo "$config" | jq -r ".profiles[\"$name\"]" 2>/dev/null)
    
    if [[ "$profile" == "null" ]]; then
        log_error "Profile '$name' not found!"
        echo
        log_info "Available profiles:"
        echo "$config" | jq -r '.profiles | keys[]' | sed 's/^/• /'
        exit 1
    fi
    
    # Show current profile details
    echo -e "${BLUE}Editing profile${NC}"
    echo "====================="
    echo -e "${PURPLE}• Profile Name${NC}: $name"

    local model_name
    model_name=$(echo "$profile" | jq -r '.model_name // "Not specified"')
    echo -e "${PURPLE}• Model Name${NC}: $model_name"

    local description
    description=$(echo "$profile" | jq -r '.description // "No description"')
    echo -e "${PURPLE}• Description${NC}: $description"

    local env_vars
    env_vars=$(echo "$profile" | jq -r '.env_vars | keys | join(", ")')
    echo -e "${PURPLE}• Environment Variables${NC}: $env_vars"
    
    while true; do
        echo
        echo '-----------------------------'
        echo "What would you like to edit?"
        log_gray "1) Profile Name"
        log_gray "2) Model Name"
        log_gray "3) Description"
        log_gray "4) Environment Variables"
        log_gray "5) Save Changes"
        log_gray "6) Discard Changes"
        echo
        echo -n "Choose option (1-6): "
        
        local choice
        if ! read -r choice; then
            log_error "Failed to read choice"
            exit 1
        fi

        case "$choice" in
            "1")
                # Edit profile name
                echo -en "${BLUE}New Profile Name${NC}: "
                local new_name
                if ! read -r new_name; then
                    log_error "Failed to read new profile name"
                    return 1
                fi
                
                new_name=$(sanitize_input "$new_name")
                if [[ -z "$new_name" ]]; then
                    log_error "Profile name cannot be empty!"
                    return 1
                fi
                
                # Validate new profile name
                if [[ ! "$new_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
                    log_error "Profile name can only contain letters, numbers, hyphens, and underscores"
                    return 1
                fi
                
                if [[ ${#new_name} -gt 50 ]]; then
                    log_error "Profile name too long (max 50 characters)"
                    return 1
                fi
                
                # Check if new name already exists
                local existing_profile
                existing_profile=$(echo "$config" | jq -r ".profiles[\"$new_name\"]" 2>/dev/null)
                if [[ "$existing_profile" != "null" ]]; then
                    log_error "Profile '$new_name' already exists!"
                    return 1
                fi
                
                # Remove old profile and add with new name
                config=$(echo "$config" | jq --arg old_name "$name" --arg new_name "$new_name" --argjson profile "$profile" 'del(.profiles[$old_name]) | .profiles[$new_name] = $profile')
                name="$new_name"  # Update name variable for success message
                log_success "Profile name changed to: $new_name"
                ;;
            "2")
                # Edit model name
                echo -en "${BLUE}New Model Name${NC}: "
                local new_model_name
                if ! read -r new_model_name; then
                    log_error "Failed to read model name"
                    return 1
                fi
                
                new_model_name=$(sanitize_input "$new_model_name")
                if [[ -z "$new_model_name" ]]; then
                    log_error "Model name cannot be empty!"
                    continue
                fi
                
                if [[ ${#new_model_name} -gt 100 ]]; then
                    log_error "Model name too long (max 100 characters)"
                    continue
                fi
                
                profile=$(echo "$profile" | jq --arg model "$new_model_name" '.model_name = $model')
                log_success "Model name updated successfully: $new_model_name"
                ;;
            "3")
                # Edit description only
                echo -en "${BLUE}New Description${NC}: "
                local new_description
                if ! read -r new_description; then
                    log_error "Failed to read description"
                    return 1
                fi
                new_description=$(sanitize_input "$new_description")
                if [[ -z "$new_description" ]]; then
                    new_description="No description provided"
                fi
                profile=$(echo "$profile" | jq --arg desc "$new_description" '.description = $desc')
                log_success "Description updated successfully: $new_description"
                ;;
            "4")
                # Edit environment variables individually
                local current_env_vars
                current_env_vars=$(echo "$profile" | jq -r '.env_vars')
                
                echo
                echo -e "${BLUE}Current environment variables${NC}"
                echo "$current_env_vars" | jq -r 'keys[]' | while read -r key; do
                    local value
                    value=$(echo "$current_env_vars" | jq -r ".[\"$key\"]")
                    local masked_value
                    if [[ ${#value} -gt 8 ]]; then
                        masked_value="${value:0:4}...${value: -4}"
                    else
                        masked_value="***"
                    fi
                    echo -e "${GREEN}• $key${NC} = $masked_value"
                done
                echo
                
                while true; do
                    echo "What would you like to do?"
                    log_gray "1) Add/Update environment variable"
                    log_gray "2) Delete environment variable"
                    log_gray "3) Cancel"
                    echo
                    echo -n "Choose option (1-3): "
                    
                    local env_choice
                    if ! read -r env_choice; then
                        log_error "Failed to read choice"
                        return 1
                    fi

                    echo '-------------------------------------'
                    
                    case "$env_choice" in
                        "1")
                            # Add new environment variable
                            echo -en "${BLUE}New Environment Variable${NC} (KEY=VALUE): "
                            local new_env_input
                            if ! read -r new_env_input; then
                                log_error "Failed to read environment variable"
                                continue
                            fi
                            
                            new_env_input=$(sanitize_input "$new_env_input")
                            if [[ ! "$new_env_input" =~ ^[A-Za-z_][A-Za-z0-9_]*=.+$ ]]; then
                                log_error "Invalid format! Use KEY=VALUE"
                                continue
                            fi
                            
                            local new_env_name="${new_env_input%%=*}"
                            local new_env_value="${new_env_input#*=}"
                            
                            if ! validate_env_key "$new_env_name" || ! validate_env_value "$new_env_value"; then
                                continue
                            fi
                            
                            # Check if key already exists
                            local existing_value
                            existing_value=$(echo "$current_env_vars" | jq -r ".[\"$new_env_name\"] // null")
                            if [[ "$existing_value" != "null" ]]; then
                                log_warning "Environment variable '$new_env_name' already exists!"
                                echo -n "Overwrite? (y/N): "
                                local overwrite_confirm
                                if ! read -r overwrite_confirm || [[ "$overwrite_confirm" != "y" && "$overwrite_confirm" != "Y" ]]; then
                                    continue
                                fi
                            fi
                            
                            current_env_vars=$(echo "$current_env_vars" | jq --arg key "$new_env_name" --arg value "$new_env_value" '.[$key] = $value')
                            log_success "Added/Updated: $new_env_name"
                            ;;
                        "2")
                            local env_keys
                            env_keys=($(echo "$current_env_vars" | jq -r 'keys[]'))
                            
                            if [[ ${#env_keys[@]} -eq 0 ]]; then
                                log_warning "No environment variables to delete!"
                                continue
                            fi
                            
                            echo -e "${BLUE}Select environment variable to delete${NC}"
                            for ((i=0; i<${#env_keys[@]}; i++)); do
                                log_gray "$((i+1)). ${env_keys[i]}"
                            done
                            echo
                            echo -n "Choose variable to delete (1-${#env_keys[@]}): "
                            
                            local delete_choice
                            if ! read -r delete_choice; then
                                log_error "Failed to read choice"
                                continue
                            fi
                            
                            if [[ ! "$delete_choice" =~ ^[0-9]+$ ]] || [[ "$delete_choice" -lt 1 ]] || [[ "$delete_choice" -gt ${#env_keys[@]} ]]; then
                                log_error "Invalid selection"
                                continue
                            fi
                            
                            local key_to_delete="${env_keys[$((delete_choice-1))]}"
                            echo -en "${RED}Are you sure you want to delete '$key_to_delete'?${NC} (y/N): "
                            local delete_confirm
                            if ! read -r delete_confirm || [[ "$delete_confirm" != "y" && "$delete_confirm" != "Y" ]]; then
                                continue
                            fi
                            
                            current_env_vars=$(echo "$current_env_vars" | jq --arg key "$key_to_delete" 'del(.[$key])')
                            log_success "Deleted: $key_to_delete"
                            ;;
                        "3")
                            log_info "Exit environment variable editing."
                            break
                            ;;
                        *)
                            log_error "Invalid option"
                            ;;
                    esac
                    echo
                done
                
                profile=$(echo "$profile" | jq --argjson env_vars "$current_env_vars" '.env_vars = $env_vars')
                ;;
            "5")
                break
                ;;
            "6"|*)
                log_info "Edit cancelled."
                return 0
                ;;
        esac
    done

    # Update the profile in config
    config=$(echo "$config" | jq --arg name "$name" --argjson profile "$profile" '.profiles[$name] = $profile')
    
    # Save configuration
    local password
    if ! password=$(get_verified_master_password); then
        return 1
    fi
    
    if ! save_session_config "$config" "$password"; then
        log_error "Failed to save configuration"
        return 1
    fi
    
    log_success "Profile '$name' updated successfully!"
}

# Delete profile with enhanced validation
cmd_delete() {
    local name="$1"
    
    if [[ -z "$name" ]]; then
        log_error "Profile name is required!"
        echo "Usage: lam delete <profile_name>"
        exit 1
    fi
    
    local config
    if ! config=$(get_session_config); then
        exit 1
    fi
    
    local profile
    profile=$(echo "$config" | jq -r ".profiles[\"$name\"]" 2>/dev/null)
    
    if [[ "$profile" == "null" ]]; then
        log_error "Profile '$name' not found!"
        echo
        log_info "Available profiles:"
        echo "$config" | jq -r '.profiles | keys[]' | sed 's/^/• /'
        exit 1
    fi
    
    # Show profile details before deletion
    echo -e "${RED}Profile to delete${NC}"
    echo "=================="
    local description
    description=$(echo "$profile" | jq -r '.description // "No description"')
    echo -e "${PURPLE}Name${NC}: $name"
    echo -e "${PURPLE}Description${NC}: $description"
    local env_vars
    env_vars=$(echo "$profile" | jq -r '.env_vars | keys | join(", ")')
    echo -e "${PURPLE}Environment Variables${NC}: $env_vars"
    echo
    
    log_warning "⚠️  This action cannot be undone!"
    echo -en "${RED}Are you sure you want to delete profile '$name'?${NC} (y/N): "
    local confirm
    if ! read -r confirm; then
        log_error "Failed to read confirmation"
        return 1
    fi
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "Deletion cancelled."
        return 0
    fi
    
    # Remove profile from config
    config=$(echo "$config" | jq --arg name "$name" 'del(.profiles[$name])')
    
    # Save configuration
    local password
    if ! password=$(get_verified_master_password); then
        return 1
    fi
    
    if ! save_session_config "$config" "$password"; then
        log_error "Failed to save configuration"
        return 1
    fi
    
    log_success "Profile '$name' deleted successfully!"
}