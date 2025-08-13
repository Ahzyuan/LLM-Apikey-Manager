#!/usr/bin/env bash

# LAM Core Commands Module
# Profile management: add, list, show, use, edit, delete

# Add new API profile with enhanced validation
cmd_add() {
    local name="$1"
    local env_vars="{}"
    local temp_collector description
    
    # profile name verification
    if [[ -z "$name" ]]; then
        log_error "Profile name is required!"
        echo "Usage: lam add <profile_name>"
        return 1
    fi
    
    if ! validate_env_key "$name" 2>/dev/null; then
        log_error "Invalid profile name format"
        log_info "Profile name must start with a letter or underscore, and contain only alphanumeric and underscore characters."
        return 1
    fi

    # auth verification
    local master_password
    if ! master_password=$(get_verified_master_password); then
        return 1
    fi
    
    if profile_exists "$name"; then
        log_warning "Profile '$name' already exists!"
        echo -en "${RED}Do you want to overwrite it? (y/N): ${NC}"
        local confirm
        if ! read -r confirm; then
            log_error "Failed to read confirmation"
            return 1
        fi
        
        if [[ $confirm != [Yy] ]]; then
            log_info "Operation cancelled."
            return 0
        fi
        
        if ! delete_profile "$name"; then
            log_error "Failed to remove existing profile"
            return 1
        fi
    fi
    
    log_info "Adding new profile: $name"
    echo '----------------------------------------------------'
    
    # Collect Model Name
    local model_name
    while true; do
        echo -en "${PURPLE}Model Name (required, e.g., gpt-4)${NC}: "
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
    
    # Collect API Key
    if temp_collector=$(
        collect_env_var "API Key" "API Key (e.g., OPENAI_API_KEY=sk-123)" \
        "$master_password" "$env_vars" \
        true true "api_key"
    ); then
        env_vars="$temp_collector"
    else
        return 1
    fi
    echo
    
    # Collect Base URL (optional)
    if temp_collector=$(
        collect_env_var "Base URL" "Base URL (optional, e.g., OPENAI_BASE_URL=https://api.openai.com/v1)" \
        "$master_password" "$env_vars" \
        false false "base_url"
    ); then
        if [[ -n "$temp_collector" ]]; then
            env_vars="$temp_collector"
        fi
    else
        return 1
    fi
    echo
    
    # Collect additional environment variables
    while true; do
        if temp_collector=$(
            collect_env_var "Additional ENV" "Additional ENV (KEY=VALUE format, or press Enter to finish)" \
            "$master_password" "$env_vars" \
            false true "other"
        ); then
            if [[ -n "$temp_collector" ]]; then
                env_vars="$temp_collector"
            else
                break
            fi
        else
            return 1
        fi
    done
    echo
    
    # Collect description
    echo -en "${PURPLE}Description (optional)${NC}: "
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
    
    # create profile 
    if ! create_profile "$name" "$model_name" "$description" "$env_vars"; then
        return 1
    fi
    
    log_success "Profile '$name' added successfully!"
    log_info "💡 To use this profile, run: source <(lam use $name)"
}

# List all profiles with enhanced formatting
cmd_list() {
    local profile_count
    profile_count=$(get_profile_count)
    
    if [[ "$profile_count" -eq 0 ]]; then
        log_info "No profiles configured yet."
        log_info "Use 'lam add <profile_name>' to add a profile."
        return 0
    fi
    
    echo
    
    # Optimized: Single SQL query to get all profile data with environment variable keys
    local profiles_data
    profiles_data=$(execute_sql "
        SELECT 
            p.name,
            p.model_name,
            p.description,
            GROUP_CONCAT(pev.key, ', ') as env_keys
        FROM profiles p
        LEFT JOIN profile_env_vars pev ON p.id = pev.profile_id
        GROUP BY p.id, p.name, p.model_name, p.description
        ORDER BY p.name;
    " true)
                
    # Process all profiles in a single loop
    while IFS='|' read -r profile_name model_name description env_keys; do
        [[ -z "$model_name" || "$model_name" == "null" ]] && model_name="Not specified"
        [[ -z "$description" || "$description" == "null" ]] && description="No description"
        [[ -z "$env_keys" || "$env_keys" == "null" ]] && env_keys="(none)"
        
        echo -e "${PURPLE}• Profile: $profile_name${NC}"
        log_gray "  ├─ Model Name: $model_name"
        log_gray "  ├─ Description: $description"
        log_gray "  └─ Environment Variables: $env_keys"
        echo
    done <<< "$profiles_data"

    log_info "💡 Get details for a profile: ${PURPLE}lam show <profile_name>${NC}"
    echo
}

# Show specific profile with secure masking
cmd_show() {
    local name="$1"
    
    if [[ -z "$name" ]]; then
        log_error "Profile name is required!"
        echo "Usage: lam show <profile_name>"
        return 1
    fi
    
    local profile
    profile=$(get_profile "$name")
    
    echo 
    echo -e "${BLUE}Profile Details${NC}"
    echo "===================="
    echo -e "${PURPLE}• Profile Name${NC}: $name"
    
    local model_name description created last_used
    model_name=$(echo "$profile" | jq -r '.model_name // "Not specified"')
    description=$(echo "$profile" | jq -r '.description // "No description"')
    created=$(echo "$profile" | jq -r '.created // "Unknown"')
    last_used=$(echo "$profile" | jq -r '.last_used // "Never"')
        
    echo -e "${PURPLE}• Model Name${NC}: $model_name"
    echo -e "${PURPLE}• Description${NC}: $description"
    
    echo
    echo -e "${PURPLE}• Created${NC}: $created"
    echo -e "${PURPLE}• Last Used${NC}: $last_used"
    
    echo 
    echo -e "${PURPLE}• Environment Variables${NC}:"
    
    local env_vars_keys
    env_vars_keys=$(echo "$profile" | jq -r '.env_vars | keys[]?' 2>/dev/null)
    
    if [[ -n "$env_vars_keys" ]]; then
        local has_vars=false
        while IFS= read -r key; do
            has_vars=true
            local encrypted_value
            encrypted_value=$(echo "$profile" | jq -r --arg k "$key" '.env_vars[$k].value' 2>/dev/null)
            
            if [[ -n "$encrypted_value" && "$encrypted_value" != "null" ]]; then
                # Mask the encrypted value for security (show first 4 and last 4 characters)
                local masked_value
                if [[ ${#encrypted_value} -gt 8 ]]; then
                    masked_value="${encrypted_value:0:4}...${encrypted_value: -4}"
                else
                    masked_value="******"
                fi
                
                echo -e "  └─ ${GREEN}$key${NC} = $masked_value"
            fi
        done <<< "$env_vars_keys"
        
        if [[ "$has_vars" == false ]]; then
            echo -e "  └─ ${GRAY}(no environment variables)${NC}"
        fi
    else
        echo -e "  └─ ${GRAY}(no environment variables)${NC}"
    fi
    
    echo '------------------------------------'
    log_gray "To use this profile: source <(lam use $name)"
    log_gray "To edit this profile: lam edit $name"
    echo 
}

# Export profile to environment variables
cmd_use() {
    local name="$1"
    
    if [[ -z "$name" ]]; then
        log_error "Profile name is required!"
        echo "Usage: lam use <profile_name>"
        return 1
    fi
    
    # Verify master password for sensitive operation
    if ! get_verified_master_password >/dev/null; then
        log_error "Authentication failed"
        return 1
    fi
        
    # Check if profile exists
    if ! profile_exists "$name"; then
        log_error "Profile '$name' not found!" >&2
        log_info "Available profiles:" >&2
        get_profile_names | sed 's/^/• /' >&2
        exit 1
    fi
    
    local profile
    profile=$(get_profile "$name")

    # Check if we're being called within eval (stdout will be captured)
    if [[ -t 1 ]]; then
        log_info "💡 To use profile ${GREEN}'$name'${NC}, run: ${PURPLE}source <(lam use $name)${NC}"
        return 0
    fi
    
    # Parse model name
    local model_name
    model_name=$(echo "$profile" | grep -o '"model_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"model_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo "unknown")
    
    # Update last used timestamp
    if ! update_profile_last_used "$name"; then
        log_error "Failed to save configuration"
        return 1
    fi
    
    # Export environment variables for shell sourcing
    echo "# LAM Profile: $name (Model: $model_name)"
    
    # Extract and export environment variables
    local exported_vars=""
    
    # Check if env_vars exists and is not empty
    if echo "$profile" | grep -q '"env_vars"[[:space:]]*:[[:space:]]*{[[:space:]]*}'; then
        # Empty env_vars object - no variables to export
        exported_vars=""
    elif echo "$profile" | grep -q '"env_vars"[[:space:]]*:[[:space:]]*{.*}'; then
        # Non-empty env_vars object
        local env_vars_section
        env_vars_section=$(echo "$profile" | grep -o '"env_vars"[[:space:]]*:[[:space:]]*{[^}]*}' | sed 's/"env_vars"[[:space:]]*:[[:space:]]*{//; s/}$//')
        
        if [[ -n "$env_vars_section" ]]; then
            while read -r pair; do
                if [[ -n "$pair" ]]; then
                    local key=$(echo "$pair" | sed 's/.*"\([^"]*\)"[[:space:]]*:.*/\1/')
                    local value=$(echo "$pair" | sed 's/.*:[[:space:]]*"\([^"]*\)".*/\1/')
                    
                    if [[ -n "$key" && -n "$value" ]]; then
                        echo "export $key='$value'"
                        if [[ -n "$exported_vars" ]]; then
                            exported_vars="$exported_vars, $key"
                        else
                            exported_vars="$key"
                        fi
                    fi
                fi
            done <<< "$(echo "$env_vars_section" | grep -o '"[^"]*"[[:space:]]*:[[:space:]]*"[^"]*"')"
        fi
    fi
    
    echo "export LLM_CURRENT_PROFILE='$name'"
    log_success "Profile ${GREEN}'$name'${NC} activated!" >&2
    log_info "Variables exported: $exported_vars, LLM_CURRENT_PROFILE" >&2
}

# Edit existing configuration with enhanced validation
cmd_edit() {
    local name="$1"
    
    if [[ -z "$name" ]]; then
        log_error "Profile name is required!"
        echo "Usage: lam edit <profile_name>"
        exit 1
    fi
    
    # Verify master password for sensitive operation
    if ! get_verified_master_password >/dev/null; then
        log_error "Authentication failed"
        exit 1
    fi
    
    # Check if profile exists
    if ! profile_exists "$name"; then
        log_error "Profile '$name' not found!"
        echo
        log_info "Available profiles:"
        get_profile_names | sed 's/^/• /'
        exit 1
    fi
    
    local profile
    profile=$(get_profile "$name")
    
    # Show current profile details
    echo -e "${BLUE}Editing profile${NC}"
    echo "====================="
    echo -e "${PURPLE}• Profile Name${NC}: $name"

    # Parse current profile data
    local model_name description
    model_name=$(echo "$profile" | grep -o '"model_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"model_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo "Not specified")
    description=$(echo "$profile" | grep -o '"description"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"description"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo "No description")

    echo -e "${PURPLE}• Model Name${NC}: $model_name"
    echo -e "${PURPLE}• Description${NC}: $description"

    # Extract environment variable keys
    local env_keys
    
    # Check if env_vars exists and is not empty
    if echo "$profile" | grep -q '"env_vars"[[:space:]]*:[[:space:]]*{[[:space:]]*}'; then
        # Empty env_vars object
        env_keys="(none)"
    elif echo "$profile" | grep -q '"env_vars"[[:space:]]*:[[:space:]]*{.*}'; then
        # Non-empty env_vars object
        local env_vars_section
        env_vars_section=$(echo "$profile" | grep -o '"env_vars"[[:space:]]*:[[:space:]]*{[^}]*}' | sed 's/"env_vars"[[:space:]]*:[[:space:]]*{//; s/}$//')
        env_keys=""
        
        if [[ -n "$env_vars_section" ]]; then
            while read -r pair; do
                if [[ -n "$pair" ]]; then
                    local key=$(echo "$pair" | sed 's/.*"\([^"]*\)"[[:space:]]*:.*/\1/')
                    if [[ -n "$env_keys" ]]; then
                        env_keys="$env_keys, $key"
                    else
                        env_keys="$key"
                    fi
                fi
            done <<< "$(echo "$env_vars_section" | grep -o '"[^"]*"[[:space:]]*:[[:space:]]*"[^"]*"')"
        fi
        
        if [[ -z "$env_keys" ]]; then
            env_keys="(none)"
        fi
    else
        env_keys="(none)"
    fi
    echo -e "${PURPLE}• Environment Variables${NC}: $env_keys"
    
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
                if profile_exists "$new_name"; then
                    log_error "Profile '$new_name' already exists!"
                    return 1
                fi
                
                # Create new profile with new name and delete old one
                local current_model_name current_description
                current_model_name=$(echo "$profile" | grep -o '"model_name"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"model_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
                current_description=$(echo "$profile" | grep -o '"description"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"description"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/')
                
                # Extract current environment variables correctly
                local current_env_vars_section
                current_env_vars_section=$(echo "$profile" | grep -o '"env_vars"[[:space:]]*:[[:space:]]*{[^}]*}' | sed 's/"env_vars"[[:space:]]*:[[:space:]]*{//; s/}$//')
                
                # Build env_vars JSON
                local env_vars_json="{"
                local first=true
                
                if [[ -n "$current_env_vars_section" ]]; then
                    while read -r pair; do
                        if [[ -n "$pair" ]]; then
                            local key=$(echo "$pair" | sed 's/.*"\([^"]*\)"[[:space:]]*:.*/\1/')
                            local value=$(echo "$pair" | sed 's/.*:[[:space:]]*"\([^"]*\)".*/\1/')
                            
                            if [[ -n "$key" && -n "$value" ]]; then
                                if [[ "$first" == true ]]; then
                                    first=false
                                else
                                    env_vars_json+=","
                                fi
                                env_vars_json+="\"$key\":\"$value\""
                            fi
                        fi
                    done <<< "$(echo "$current_env_vars_section" | grep -o '"[^"]*"[[:space:]]*:[[:space:]]*"[^"]*"')"
                fi
                
                env_vars_json+="}"
                
                # Create new profile and delete old one
                if create_profile "$new_name" "$current_model_name" "$current_description" "$env_vars_json" && delete_profile "$name"; then
                    name="$new_name"  # Update name variable for success message
                    profile=$(get_profile "$name")  # Refresh profile data
                    log_success "Profile name changed to: $new_name"
                else
                    log_error "Failed to rename profile"
                    return 1
                fi
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
                
                # Update model name in database
                if update_profile "$name" "$new_model_name" "" ""; then
                    profile=$(get_profile "$name")  # Refresh profile data
                    log_success "Model name updated successfully: $new_model_name"
                else
                    log_error "Failed to update model name"
                    return 1
                fi
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
                
                # Update description in database
                if update_profile "$name" "" "$new_description" ""; then
                    profile=$(get_profile "$name")  # Refresh profile data
                    log_success "Description updated successfully: $new_description"
                else
                    log_error "Failed to update description"
                    return 1
                fi
                ;;
            "4")
                # Edit environment variables individually
                echo
                echo -e "${BLUE}Current environment variables${NC}"
                
                # Extract and display current environment variables
                # Check if env_vars exists and is not empty
                if echo "$profile" | grep -q '"env_vars"[[:space:]]*:[[:space:]]*{[[:space:]]*}'; then
                    # Empty env_vars object
                    echo -e "${GRAY}(no environment variables)${NC}"
                elif echo "$profile" | grep -q '"env_vars"[[:space:]]*:[[:space:]]*{.*}'; then
                    # Non-empty env_vars object
                    local env_vars_section
                    env_vars_section=$(echo "$profile" | grep -o '"env_vars"[[:space:]]*:[[:space:]]*{[^}]*}' | sed 's/"env_vars"[[:space:]]*:[[:space:]]*{//; s/}$//')
                    
                    if [[ -n "$env_vars_section" ]]; then
                        local found_vars=false
                        while read -r pair; do
                            if [[ -n "$pair" ]]; then
                                found_vars=true
                                local key=$(echo "$pair" | sed 's/.*"\([^"]*\)"[[:space:]]*:.*/\1/')
                                local value=$(echo "$pair" | sed 's/.*:[[:space:]]*"\([^"]*\)".*/\1/')
                                
                                local masked_value
                                if [[ ${#value} -gt 8 ]]; then
                                    masked_value="${value:0:4}...${value: -4}"
                                else
                                    masked_value="***"
                                fi
                                echo -e "${GREEN}• $key${NC} = $masked_value"
                            fi
                        done <<< "$(echo "$env_vars_section" | grep -o '"[^"]*"[[:space:]]*:[[:space:]]*"[^"]*"')"
                        
                        if [[ "$found_vars" == false ]]; then
                            echo -e "${GRAY}(no environment variables)${NC}"
                        fi
                    else
                        echo -e "${GRAY}(no environment variables)${NC}"
                    fi
                else
                    echo -e "${GRAY}(no environment variables)${NC}"
                fi
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
                            
                            # Get current env vars and check if key exists
                            local current_profile_json current_env_vars_section
                            current_profile_json=$(get_profile "$name")
                            current_env_vars_section=$(echo "$current_profile_json" | grep -o '"env_vars"[[:space:]]*:[[:space:]]*{[^}]*}' | sed 's/"env_vars"[[:space:]]*:[[:space:]]*{//; s/}$//')
                            
                            local key_exists=false
                            if [[ -n "$current_env_vars_section" ]]; then
                                while read -r pair; do
                                    if [[ -n "$pair" ]]; then
                                        local existing_key=$(echo "$pair" | sed 's/.*"\([^"]*\)"[[:space:]]*:.*/\1/')
                                        if [[ "$existing_key" == "$new_env_name" ]]; then
                                            key_exists=true
                                            break
                                        fi
                                    fi
                                done <<< "$(echo "$current_env_vars_section" | grep -o '"[^"]*"[[:space:]]*:[[:space:]]*"[^"]*"')"
                            fi
                            
                            if [[ "$key_exists" == true ]]; then
                                log_warning "Environment variable '$new_env_name' already exists!"
                                echo -n "Overwrite? (y/N): "
                                local overwrite_confirm
                                if ! read -r overwrite_confirm || [[ "$overwrite_confirm" != "y" && "$overwrite_confirm" != "Y" ]]; then
                                    continue
                                fi
                            fi
                            
                            # Build new env vars JSON
                            local new_env_vars_json="{"
                            local first=true
                            
                            # Add existing vars (except the one we're updating)
                            if [[ -n "$current_env_vars_section" ]]; then
                                while read -r pair; do
                                    if [[ -n "$pair" ]]; then
                                        local existing_key=$(echo "$pair" | sed 's/.*"\([^"]*\)"[[:space:]]*:.*/\1/')
                                        local existing_value=$(echo "$pair" | sed 's/.*:[[:space:]]*"\([^"]*\)".*/\1/')
                                        
                                        if [[ "$existing_key" != "$new_env_name" ]]; then
                                            if [[ "$first" == true ]]; then
                                                first=false
                                            else
                                                new_env_vars_json+=","
                                            fi
                                            new_env_vars_json+="\"$existing_key\":\"$existing_value\""
                                        fi
                                    fi
                                done <<< "$(echo "$current_env_vars_section" | grep -o '"[^"]*"[[:space:]]*:[[:space:]]*"[^"]*"')"
                            fi
                            
                            # Add the new/updated variable
                            if [[ "$first" == true ]]; then
                                first=false
                            else
                                new_env_vars_json+=","
                            fi
                            new_env_vars_json+="\"$new_env_name\":\"$new_env_value\""
                            new_env_vars_json+="}"
                            
                            # Update profile with new env vars
                            if update_profile "$name" "" "" "$new_env_vars_json"; then
                                profile=$(get_profile "$name")  # Refresh profile data
                                log_success "Added/Updated: $new_env_name"
                            else
                                log_error "Failed to update environment variable"
                                return 1
                            fi
                            ;;
                        "2")
                            # Get current environment variables
                            local current_profile_json current_env_vars_section
                            current_profile_json=$(get_profile "$name")
                            current_env_vars_section=$(echo "$current_profile_json" | grep -o '"env_vars"[[:space:]]*:[[:space:]]*{[^}]*}' | sed 's/"env_vars"[[:space:]]*:[[:space:]]*{//; s/}$//')
                            
                            # Build array of env var keys
                            local env_keys=()
                            if [[ -n "$current_env_vars_section" ]]; then
                                while read -r pair; do
                                    if [[ -n "$pair" ]]; then
                                        local key=$(echo "$pair" | sed 's/.*"\([^"]*\)"[[:space:]]*:.*/\1/')
                                        env_keys+=("$key")
                                    fi
                                done <<< "$(echo "$current_env_vars_section" | grep -o '"[^"]*"[[:space:]]*:[[:space:]]*"[^"]*"')"
                            fi
                            
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
                            
                            # Build new env vars JSON without the deleted key
                            local new_env_vars_json="{"
                            local first=true
                            if [[ -n "$current_env_vars_section" ]]; then
                                while read -r pair; do
                                    if [[ -n "$pair" ]]; then
                                        local existing_key=$(echo "$pair" | sed 's/.*"\([^"]*\)"[[:space:]]*:.*/\1/')
                                        local existing_value=$(echo "$pair" | sed 's/.*:[[:space:]]*"\([^"]*\)".*/\1/')
                                        
                                        if [[ "$existing_key" != "$key_to_delete" ]]; then
                                            if [[ "$first" == true ]]; then
                                                first=false
                                            else
                                                new_env_vars_json+=","
                                            fi
                                            new_env_vars_json+="\"$existing_key\":\"$existing_value\""
                                        fi
                                    fi
                                done <<< "$(echo "$current_env_vars_section" | grep -o '"[^"]*"[[:space:]]*:[[:space:]]*"[^"]*"')"
                            fi
                            new_env_vars_json+="}"
                            
                            # Update profile
                            if update_profile "$name" "" "" "$new_env_vars_json"; then
                                profile=$(get_profile "$name")  # Refresh profile data
                                log_success "Deleted: $key_to_delete"
                            else
                                log_error "Failed to delete environment variable"
                                return 1
                            fi
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
    
    # Verify master password for sensitive operation
    if ! get_verified_master_password >/dev/null; then
        log_error "Authentication failed"
        exit 1
    fi
    
    # Check if profile exists
    if ! profile_exists "$name"; then
        log_error "Profile '$name' not found!"
        echo
        log_info "Available profiles:"
        get_profile_names | sed 's/^/• /'
        exit 1
    fi
    
    local profile
    profile=$(get_profile "$name")
    
    # Show profile details before deletion
    echo -e "${RED}Profile to delete${NC}"
    echo "=================="
    
    # Parse profile data
    local description env_keys
    description=$(echo "$profile" | grep -o '"description"[[:space:]]*:[[:space:]]*"[^"]*"' | sed 's/.*"description"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/' || echo "No description")
    
    # Extract environment variable keys
    local env_keys
    
    # Check if env_vars exists and is not empty
    if echo "$profile" | grep -q '"env_vars"[[:space:]]*:[[:space:]]*{[[:space:]]*}'; then
        # Empty env_vars object
        env_keys="(none)"
    elif echo "$profile" | grep -q '"env_vars"[[:space:]]*:[[:space:]]*{.*}'; then
        # Non-empty env_vars object
        local env_vars_section
        env_vars_section=$(echo "$profile" | grep -o '"env_vars"[[:space:]]*:[[:space:]]*{[^}]*}' | sed 's/"env_vars"[[:space:]]*:[[:space:]]*{//; s/}$//')
        env_keys=""
        
        if [[ -n "$env_vars_section" ]]; then
            while read -r pair; do
                if [[ -n "$pair" ]]; then
                    local key=$(echo "$pair" | sed 's/.*"\([^"]*\)"[[:space:]]*:.*/\1/')
                    if [[ -n "$env_keys" ]]; then
                        env_keys="$env_keys, $key"
                    else
                        env_keys="$key"
                    fi
                fi
            done <<< "$(echo "$env_vars_section" | grep -o '"[^"]*"[[:space:]]*:[[:space:]]*"[^"]*"')"
        fi
        
        if [[ -z "$env_keys" ]]; then
            env_keys="(none)"
        fi
    else
        env_keys="(none)"
    fi
    
    echo -e "${PURPLE}Name${NC}: $name"
    echo -e "${PURPLE}Description${NC}: $description"
    echo -e "${PURPLE}Environment Variables${NC}: $env_keys"
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
    
    # Delete profile from database
    if ! delete_profile "$name"; then
        log_error "Failed to delete profile"
        return 1
    fi
    
    log_success "Profile '$name' deleted successfully!"
}