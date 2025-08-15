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
        log_info "Usage: lam add <profile_name>"
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
    
    log_success "Profile ${PURPLE}'$name'${NC} added successfully!"
    log_info "💡 To use this profile, run: ${NC}source <(lam use $name)${NC}"
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
    
    check_profile_arg "$name"
    
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
    
    check_profile_arg "$name"
    
    local master_password
    if ! master_password=$(get_verified_master_password); then
        return 1
    fi
    
    local profile
    profile=$(get_profile "$name")

    # Check if we're being called within source
    if [[ -t 1 ]]; then
        log_info "💡 To use profile ${PURPLE}'$name'${NC}, run: ${PURPLE}source <(lam use $name)${NC}"
        return 0
    fi
    
    local model_name
    model_name=$(echo "$profile" | jq -r '.model_name // "unknown"')
    
    # Update last used timestamp
    if ! update_profile_last_used "$name" 2>/dev/null; then
        log_warning "Failed to update last used timestamp" >&2
    fi
    
    # Extract and export environment variables using jq
    local exported_vars=""
    local env_keys
    log_info "Loading profile ${PURPLE}'$name'${NC}..." >&2
    env_keys=$(echo "$profile" | jq -r '.env_vars | keys[]?' 2>/dev/null)
    
    if [[ -n "$env_keys" ]]; then
        while IFS= read -r key; do
            local encrypted_value
            encrypted_value=$(echo "$profile" | jq -r --arg k "$key" '.env_vars[$k].value' 2>/dev/null)
        
            if [[ -n "$encrypted_value" && "$encrypted_value" != "null" ]]; then
                local decrypted_value
                if ! decrypted_value=$(decrypt_data "$encrypted_value" "$master_password"); then
                    log_error "Failed to decrypt environment variable: $key" >&2
                    exit 1
                fi
                
                echo "export $key='$decrypted_value'"
                if [[ -n "$exported_vars" ]]; then
                    exported_vars="$exported_vars, ${GREEN}$key${NC}"
                else
                    exported_vars="${GREEN}$key${NC}"
                fi
            fi
        done <<< "$env_keys"
        echo "export LLM_CURRENT_PROFILE=$name"
        
        log_success "Profile ${PURPLE}'$name'${NC} activated!" >&2
        log_info "Variables exported: $exported_vars" >&2
    else
        log_info "No environment variables found for profile ${PURPLE}'$name'${NC}" >&2
    fi
}

# Edit existing configuration with enhanced validation
cmd_edit() {
    local name="$1"
    
    check_profile_arg "$name"

    local master_password
    if ! master_password=$(get_verified_master_password); then
        return 1
    fi
    
    local profile
    profile=$(get_profile "$name")
    
    local original_model_name original_description original_env_vars
    original_model_name=$(echo "$profile" | jq -r '.model_name // "Not specified"')
    original_description=$(echo "$profile" | jq -r '.description // "No description"')
    original_env_vars=$(echo "$profile" | jq -c '.env_vars // {}')
    
    local profile_name="$name"
    local model_name="$original_model_name"
    local description="$original_description"
    local env_vars_json="$original_env_vars"
    local has_changes=false
    local name_changed=false

    local env_keys
    local env_keys_list
    env_keys_list=$(echo "$profile" | jq -r '.env_vars | keys[]?' 2>/dev/null)
    
    if [[ -n "$env_keys_list" ]]; then
        local keys_array=()
        mapfile -t keys_array <<< "$env_keys_list"
        
        env_keys=$(printf "%s, " "${keys_array[@]}")
        env_keys="${env_keys%, }"  # Remove trailing comma
    else
        env_keys="(none)"
    fi

    # Show current profile details
    echo -e "${BLUE}Editing profile${NC}"
    echo "====================="
    echo -e "${PURPLE}• Profile Name${NC}: $name"
    echo -e "${PURPLE}• Model Name${NC}: $model_name"
    echo -e "${PURPLE}• Description${NC}: $description"
    echo -e "${PURPLE}• Environment Variables${NC}: $env_keys"
    
    while true; do
        echo
        echo '-----------------------------'
        echo "What would you like to edit?"
        log_gray "1) Profile Name"
        log_gray "2) Model Name"
        log_gray "3) Description"
        log_gray "4) Environment Variables"
        log_gray "5) Save Changes and exit"
        log_gray "6) Discard Changes and exit"
        echo
        echo -n "Choose option (1-6): "
        
        local choice
        if ! read -r choice; then
            log_error "Failed to read choice"
            exit 1
        fi

        case "$choice" in
            "1")
                echo -en "${BLUE}Enter new profile name${NC}: "
                local new_name
                if ! read -r new_name; then
                    log_error "Failed to read new profile name"
                    continue
                fi
                
                new_name=$(sanitize_input "$new_name")
                if [[ -z "$new_name" ]]; then
                    log_error "Profile name cannot be empty"
                    continue
                fi
                
                if [[ "$new_name" == "$profile_name" ]]; then
                    log_info "Profile name unchanged"
                    continue
                fi
                
                if profile_exists "$new_name"; then
                    log_error "Profile '$new_name' already exists"
                    continue
                fi
                
                # Update profile name in memory
                profile_name="$new_name"
                name_changed=true
                has_changes=true
                log_success "Profile name updated: $new_name"
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
                
                model_name="$new_model_name"
                has_changes=true
                log_success "Model name updated: $new_model_name"
                ;;
            "3")
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
                
                description="$new_description"
                has_changes=true
                log_success "Description updated: $new_description"
                ;;
            "4")
                echo
                echo -e "${BLUE}Current environment variables:${NC}"
                
                local env_vars_data
                env_vars_data=$(echo "$env_vars_json" | jq -r 'to_entries[] | "\(.key)|\(.value.value)"' 2>/dev/null)
                
                if [[ -n "$env_vars_data" ]]; then
                    while IFS='|' read -r key encrypted_value; do
                        if [[ -n "$key" && -n "$encrypted_value" && "$encrypted_value" != "null" ]]; then
                            local decrypted_value
                            if decrypted_value=$(decrypt_data "$encrypted_value" "$master_password" 2>/dev/null); then
                                echo -e "└─ ${GREEN}• $key${NC} = $decrypted_value"
                            else
                                echo -e "└─ ${GREEN}• $key${NC} = ${RED}[DECRYPT ERROR]${NC}"
                            fi
                        fi
                    done <<< "$env_vars_data"
                    
                else
                    log_gray "└─ (no environment variables)"
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
                            
                            # Encrypt the new environment variable value
                            local encrypted_new_env_value
                            if ! encrypted_new_env_value=$(encrypt_data "$new_env_value" "$master_password" 2>/dev/null); then
                                log_error "Failed to encrypt environment variable value"
                                exit 1
                            fi
                            
                            while true; do 
                                echo
                                echo -e "${BLUE}Select environment variable type:${NC}"
                                log_gray "1) API Key (for authentication keys)"
                                log_gray "2) Base URL (for API endpoints)"
                                log_gray "3) Other (for custom variables)"
                                echo
                                echo -n "Choose type (1-3): "
                                
                                local type_choice env_type
                                if ! read -r type_choice; then
                                    log_error "Failed to read type choice"
                                    continue
                                fi
                            
                                case "$type_choice" in
                                    "1")
                                        env_type="api_key"
                                        log_info "Selected: API Key"
                                        break
                                        ;;
                                    "2")
                                        env_type="base_url"
                                        log_info "Selected: Base URL"
                                        break
                                        ;;
                                    "3")
                                        env_type="other"
                                        log_info "Selected: Other"
                                        break
                                        ;;
                                    *)
                                        log_error "Invalid selection"
                                        continue
                                        ;;
                                esac
                            done
                            
                            # Create new environment variable object with user-selected type
                            local new_env_object
                            new_env_object=$(jq -n --arg value "$encrypted_new_env_value" --arg type "$env_type" '{value: $value, type: $type}')
                            
                            # Add/update the environment variable in working copy using jq
                            env_vars_json=$(echo "$env_vars_json" | jq --arg key "$new_env_name" --argjson obj "$new_env_object" '.[$key] = $obj')
                            has_changes=true
                            log_success "Added/Updated: $new_env_name"
                            ;;
                        "2")
                            local env_keys=()
                            local env_keys_list
                            env_keys_list=$(echo "$env_vars_json" | jq -r 'keys[]?' 2>/dev/null)
                            
                            if [[ -n "$env_keys_list" ]]; then
                                mapfile -t env_keys <<< "$env_keys_list"
                            fi
                            
                            if [[ ${#env_keys[@]} -eq 0 ]]; then
                                log_info "No environment variables to delete!"
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
                            
                            if [[ ! "$delete_choice" =~ ^[0-9]+$ ]] || \
                               [[ "$delete_choice" -lt 1 ]] || \
                               [[ "$delete_choice" -gt ${#env_keys[@]} ]]; then
                                log_error "Invalid selection"
                                continue
                            fi
                            
                            local key_to_delete="${env_keys[$((delete_choice-1))]}"
                            echo -en "${RED}Are you sure you want to delete '$key_to_delete'?${NC} (y/N): "
                            local delete_confirm
                            if ! read -r delete_confirm || [[ "$delete_confirm" != "y" && "$delete_confirm" != "Y" ]]; then
                                continue
                            fi
                            
                            env_vars_json=$(echo "$env_vars_json" | jq --arg key "$key_to_delete" 'del(.[$key])')
                            has_changes=true
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
                
                ;;
            "5")
                if $has_changes; then
                    # Handle profile name change (requires create new + delete old)
                    if $name_changed; then
                        if create_profile "$profile_name" "$model_name" "$description" "$env_vars_json"; then
                            if delete_profile "$name" "true" 2>/dev/null; then
                                log_success "Profile renamed from ${PURPLE}'$name'${NC} to ${PURPLE}'$profile_name'${NC}"
                            else
                                log_warning "Failed to delete old profile. You may have duplicate profiles."
                                log_warning "You can manually delete the old profile with ${PURPLE}'lam delete $name'${NC}"
                            fi
                        else
                            log_error "Failed to create new profile with name ${PURPLE}'$profile_name'${NC}"
                            return 1
                        fi
                    else
                        if ! update_profile "$name" "$model_name" "$description" "$env_vars_json"; then
                            log_error "Failed to save changes to profile ${PURPLE}'$name'${NC}"
                            return 1
                        fi
                    fi
                    
                    echo 
                    log_success "Profile ${PURPLE}'$profile_name'${NC} updated successfully!"
                    if [[ "$name_changed" == true ]]; then
                        log_info "• Profile Name: ${PURPLE}$name${NC} → ${PURPLE}$profile_name${NC}"
                    fi
                    if [[ "$model_name" != "$original_model_name" ]]; then
                        log_info "• Model Name: ${PURPLE}$original_model_name${NC} → $model_name${NC}"
                    fi
                    if [[ "$description" != "$original_description" ]]; then
                        log_info "• Description: ${PURPLE}$original_description${NC} → $description${NC}"
                    fi
                    if [[ "$env_vars_json" != "$original_env_vars" ]]; then
                        log_info "• Environment Variables: Updated"
                    fi
                else
                    log_info "No changes to save."
                fi
                break
                ;;
            "6")
                return 0
                ;;
            *)
                log_error "Invalid option"
                continue
                ;;
        esac        
    done
}

# Delete profile with enhanced validation
cmd_delete() {
    local name="$1"
    local arg_error=false
    
    check_profile_arg "$name"
    
    local master_password
    if ! master_password=$(get_verified_master_password); then
        return 1
    fi
    
    local profile
    profile=$(get_profile "$name")
    
    # Show profile details before deletion
    echo -e "${RED}Profile to delete${NC}"
    echo "=================="
    
    local model_name description
    model_name=$(echo "$profile" | jq -r '.model_name // "Not specified"')
    description=$(echo "$profile" | jq -r '.description // "No description"')
    
    local env_keys
    local env_keys_list
    env_keys_list=$(echo "$profile" | jq -r '.env_vars | keys[]?' 2>/dev/null)
    
    if [[ -n "$env_keys_list" ]]; then
        local keys_array=()
        mapfile -t keys_array <<< "$env_keys_list"
        
        env_keys=$(printf "%s, " "${keys_array[@]}")
        env_keys="${env_keys%, }"  # Remove trailing comma
    else
        env_keys="(none)"
    fi
    
    echo -e "${PURPLE}Profile Name${NC}: $name"
    echo -e "${PURPLE}Model Name${NC}: $model_name"
    echo -e "${PURPLE}Description${NC}: $description"
    echo -e "${PURPLE}Environment Variables${NC}: $env_keys"
    echo
    
    log_warning "⚠️  This action cannot be undone!"
    echo -en "${RED}Are you sure you want to delete profile ${PURPLE}'$name'${RED}?${NC} (y/N): "
    local confirm
    if ! read -r confirm; then
        log_error "Failed to read confirmation"
        return 1
    fi
    
    if [[ $confirm != [Yy] ]]; then
        log_info "Deletion cancelled."
        return 0
    fi
    
    delete_profile "$name" || return 1
}