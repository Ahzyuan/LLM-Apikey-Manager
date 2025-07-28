#!/bin/bash

# LAM Commands Module
# All command implementations

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
    local initial_config='{"profiles":{},"metadata":{"created":"'$(date -Iseconds)'","version":"3.1.0"}}'
    
    if ! save_session_config "$initial_config" "$password"; then
        log_error "Failed to save initial configuration"
        return 1
    fi
    
    log_success "LAM initialized successfully!"
    echo
    log_info "You can now add API configurations using: lam add <profile_name>"
}

# Add new API configuration with enhanced validation
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
        echo -n "Do you want to overwrite it? (y/N): "
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
    
    log_info "Adding new API configuration: $name"
    echo
    log_info "Enter your API configuration details:"
    echo
    
    # Initialize empty env_vars object
    local env_vars='{}'
    
    # Collect API Key
    echo -n "API Key (e.g., OPENAI_API_KEY=sk-123... or API_KEY=your_key): "
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
    
    # Collect Base URL
    echo -n "Base URL (e.g., BASE_URL=https://api.openai.com/v1): "
    local base_url_input
    if ! read -r base_url_input; then
        log_error "Failed to read base URL"
        return 1
    fi
    
    # Validate and parse base URL input
    base_url_input=$(sanitize_input "$base_url_input")
    if [[ ! "$base_url_input" =~ ^[A-Za-z_][A-Za-z0-9_]*=.+$ ]]; then
        log_error "Invalid format! Use KEY=VALUE (e.g., BASE_URL=https://api.openai.com/v1)"
        return 1
    fi
    
    local base_url_name="${base_url_input%%=*}"
    local base_url_value="${base_url_input#*=}"
    
    if ! validate_env_key "$base_url_name" || ! validate_env_value "$base_url_value"; then
        return 1
    fi
    
    # Validate URL format
    if [[ ! "$base_url_value" =~ ^https?://[a-zA-Z0-9.-]+[a-zA-Z0-9./:-]*$ ]]; then
        log_error "Invalid URL format: $base_url_value"
        return 1
    fi
    
    env_vars=$(echo "$env_vars" | jq --arg key "$base_url_name" --arg value "$base_url_value" '.[$key] = $value')
    log_success "Added: $base_url_name=$base_url_value"
    
    # Collect additional environment variables
    echo
    echo "Additional environment variables (optional):"
    while true; do
        echo -n "Environment variable (KEY=VALUE, or press Enter to continue): "
        local env_input
        if ! read -r env_input; then
            log_error "Failed to read input"
            return 1
        fi
        
        # If empty input, break the loop
        if [[ -z "$env_input" ]]; then
            break
        fi
        
        # Sanitize and validate
        env_input=$(sanitize_input "$env_input")
        
        if ! validate_input_length "$env_input"; then
            continue
        fi
        
        # Validate KEY=VALUE format
        if [[ ! "$env_input" =~ ^[A-Za-z_][A-Za-z0-9_]*=.+$ ]]; then
            log_error "Invalid format! Use KEY=VALUE (e.g., MODEL_NAME=gpt-4)"
            continue
        fi
        
        # Extract key and value
        local key="${env_input%%=*}"
        local value="${env_input#*=}"
        
        # Validate key and value
        if ! validate_env_key "$key" || ! validate_env_value "$value"; then
            continue
        fi
        
        # Add to env_vars JSON
        env_vars=$(echo "$env_vars" | jq --arg key "$key" --arg value "$value" '.[$key] = $value') || {
            log_error "Failed to add environment variable to JSON"
            continue
        }
        
        log_success "Added: $key=***"
    done
    
    # Collect model name
    echo -n "Model Name (optional, e.g., gpt-4): "
    local model_name
    if ! read -r model_name; then
        log_error "Failed to read model name"
        return 1
    fi
    model_name=$(sanitize_input "$model_name")
    
    # Collect description
    echo -n "Description (optional): "
    local description
    if ! read -r description; then
        log_error "Failed to read description"
        return 1
    fi
    description=$(sanitize_input "$description")
    
    # Create profile object
    local profile
    profile=$(jq -n \
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
        }') || {
        log_error "Failed to create profile JSON"
        return 1
    }
    
    # Add to configuration
    config=$(echo "$config" | jq --arg name "$name" --argjson profile "$profile" '.profiles[$name] = $profile') || {
        log_error "Failed to add profile to configuration"
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
    
    log_success "Profile '$name' added successfully!"
    echo
    log_info "Environment variables: $(echo "$env_vars" | jq -r 'keys | join(", ")')"
    echo
    log_info "You can now use it with: eval \"\$(lam use $name)\""
}

# List all configurations with enhanced formatting
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

# Show version information
cmd_version() {
    echo "LAM (LLM API Manager) v3.1.0 (Security Hardened)"
    echo "Enhanced with security improvements and better error handling"
}

# Show help
cmd_help() {
    cat << 'EOF'
LAM (LLM API Manager) v3.1.0 - Secure management of LLM API credentials

USAGE:
    lam <command> [arguments]

COMMANDS:
    init                    Initialize the tool with master password
    add <n>              Add new API configuration
    list                    List all configurations
    show <n>             Show configuration details (masked values)
    use <n>              Export configuration to environment variables
    edit <n>             Edit existing configuration
    delete <n>           Delete configuration
    status                  Show LAM status and statistics
    test                    Test API connection for current profile
    backup [file]           Backup all profiles
    update                  Update LAM to latest version
    uninstall               Completely remove LAM from system
    help                    Show this help message
    --version               Show version information

SECURITY IMPROVEMENTS:
    - Enhanced password validation and secure input handling
    - Protection against command injection attacks
    - Atomic file operations to prevent race conditions
    - Comprehensive input validation and sanitization
    - Improved error handling and cleanup mechanisms

For detailed examples and usage, see the README.md file.
EOF
}

# Show specific configuration with secure masking
cmd_show() {
    local name="$1"
    
    if [[ -z "$name" ]]; then
        log_error "Profile name is required!"
        echo "Usage: lam show <profile_name>"
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
    
    local profile
    profile=$(echo "$config" | jq -r ".profiles[\"$name\"]" 2>/dev/null)
    
    if [[ "$profile" == "null" ]]; then
        log_error "Profile '$name' not found!"
        return 1
    fi
    
    echo "Profile: $name"
    echo "=============="
    
    local env_vars
    env_vars=$(echo "$profile" | jq -r '.env_vars')
    
    echo "Environment Variables:"
    echo "$env_vars" | jq -r 'to_entries[] | "  \(.key) = \(.value | if length > 10 then .[:10] + "..." else . end)"'
    
    local model_name
    model_name=$(echo "$profile" | jq -r '.model_name // "Not specified"')
    echo "Model: $model_name"
    
    local description
    description=$(echo "$profile" | jq -r '.description // "No description"')
    echo "Description: $description"
    
    local created
    created=$(echo "$profile" | jq -r '.created // "Unknown"')
    echo "Created: $created"
    
    local last_used
    last_used=$(echo "$profile" | jq -r '.last_used // "Never"')
    echo "Last Used: $last_used"
}

# Export configuration to environment variables with enhanced security
cmd_use() {
    local name="$1"
    
    if [[ -z "$name" ]]; then
        log_error "Profile name is required!"
        echo "Usage: lam use <profile_name>"
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
    
    local profile
    profile=$(echo "$config" | jq -r ".profiles[\"$name\"]" 2>/dev/null)
    
    if [[ "$profile" == "null" ]]; then
        log_error "Profile '$name' not found!"
        return 1
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
    
    # Check if we're being called within eval (stdout will be captured)
    if [[ -t 1 ]]; then
        # Interactive mode - show helpful information
        local exported_vars
        exported_vars=$(echo "$env_vars" | jq -r 'keys | join(", ")')
        echo
        log_success "Profile '$name' activated!"
        echo
        log_info "Variables ready for export:"
        echo "  • $exported_vars"
        echo "  • LLM_CURRENT_PROFILE"
        if [[ "$model_name" != "null" && -n "$model_name" ]]; then
            echo "  • MODEL_NAME ($model_name)"
        fi
        echo
        log_info "💡 TO EXPORT VARIABLES TO YOUR SHELL, Run this command:"
        log_gray "    eval \"\$(lam use $name)\""
        echo
    else
        # Non-interactive mode (being eval'd) - output export commands
        echo "$env_vars" | jq -r 'to_entries[] | "export \(.key)='"'"'\(.value)'"'"'"'
        echo "export LLM_CURRENT_PROFILE='$name'"
        if [[ "$model_name" != "null" && -n "$model_name" ]]; then
            echo "export MODEL_NAME='$model_name'"
        fi
    fi
}


# Edit existing configuration with enhanced validation
cmd_edit() {
    local name="$1"
    
    if [[ -z "$name" ]]; then
        log_error "Profile name is required!"
        echo "Usage: lam edit <profile_name>"
        return 1
    fi
    
    local config
    config=$(get_session_config)
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    local profile=$(echo "$config" | jq -r ".profiles[\"$name\"]" 2>/dev/null)
    
    if [[ "$profile" == "null" ]]; then
        log_error "Profile '$name' not found!"
        return 1
    fi
    
    # Show current values and prompt for new ones
    echo "Editing profile: $name"
    echo "=================="
    
    local current_env_vars=$(echo "$profile" | jq -r '.env_vars')
    local current_model_name=$(echo "$profile" | jq -r '.model_name // ""')
    local current_description=$(echo "$profile" | jq -r '.description // ""')
    
    echo "Current environment variables:"
    echo "$current_env_vars" | jq -r 'to_entries[] | 
        if (.value | length) >= 12 then 
            "  \(.key): \(.value[:4])...\(.value[-4:])" 
        else 
            "  \(.key): \(.value[:4])***" 
        end'
    echo
    
    echo "Choose what to edit:"
    echo "1. Environment variables"
    echo "2. Model name"
    echo "3. Description"
    echo "4. All of the above"
    echo -n "Enter choice (1-4): "
    read -r choice
    
    local new_env_vars="$current_env_vars"
    local new_model_name="$current_model_name"
    local new_description="$current_description"
    
    if [[ "$choice" == "1" || "$choice" == "4" ]]; then
        echo
        log_info "Edit environment variables:"
        echo "Current variables:"
        echo "$current_env_vars" | jq -r 'to_entries[] | "  \(.key)=\(.value[:8])...\(.value[-4:])"'
        echo
        
        while true; do
            echo "Options:"
            echo "1. Add/modify a variable"
            echo "2. Delete a variable"
            echo "3. Done editing variables"
            echo -n "Choose (1-3): "
            read -r var_choice
            
            case "$var_choice" in
                "1")
                    echo -n "Environment variable (KEY=VALUE): "
                    read -r env_input
                    
                    if [[ ! "$env_input" =~ ^[A-Z_][A-Z0-9_]*=[[:print:]]+$ ]]; then
                        log_error "Invalid format! Use KEY=VALUE (e.g., API_KEY=sk-123...)"
                        continue
                    fi
                    
                    local key="${env_input%%=*}"
                    local value="${env_input#*=}"
                    
                    new_env_vars=$(echo "$new_env_vars" | jq --arg key "$key" --arg value "$value" '. + {($key): $value}')
                    log_success "Updated: $key=***"
                    ;;
                "2")
                    echo "Current variables:"
                    echo "$new_env_vars" | jq -r 'keys[]' | nl -v1
                    echo -n "Enter variable name to delete: "
                    read -r delete_key
                    
                    if echo "$new_env_vars" | jq -e --arg key "$delete_key" 'has($key)' >/dev/null; then
                        new_env_vars=$(echo "$new_env_vars" | jq --arg key "$delete_key" 'del(.[$key])')
                        log_success "Deleted: $delete_key"
                    else
                        log_error "Variable '$delete_key' not found!"
                    fi
                    ;;
                "3")
                    # Check if at least one variable remains
                    if [[ $(echo "$new_env_vars" | jq 'length') -eq 0 ]]; then
                        log_error "At least one environment variable is required!"
                        continue
                    fi
                    break
                    ;;
                *)
                    log_error "Invalid choice! Please enter 1, 2, or 3."
                    ;;
            esac
        done
    fi
    
    if [[ "$choice" == "2" || "$choice" == "4" ]]; then
        echo
        echo "Current model: $current_model_name"
        echo -n "New model name (press Enter to keep current): "
        read -r new_model_name
        new_model_name=${new_model_name:-$current_model_name}
    fi
    
    if [[ "$choice" == "3" || "$choice" == "4" ]]; then
        echo
        echo "Current description: $current_description"
        echo -n "New description (press Enter to keep current): "
        read -r new_description
        new_description=${new_description:-$current_description}
    fi
    
    # Update profile
    local updated_profile=$(echo "$profile" | jq \
        --argjson env_vars "$new_env_vars" \
        --arg model_name "$new_model_name" \
        --arg description "$new_description" \
        '.env_vars = $env_vars | .model_name = $model_name | .description = $description')
    
    config=$(echo "$config" | jq ".profiles[\"$name\"] = $updated_profile")
    
    # We need the password to save, get it once
    local password
    password=$(get_verified_master_password)
    if [[ $? -ne 0 ]]; then
        return 1
    fi
    
    save_session_config "$config" "$password"
    
    log_success "Profile '$name' updated successfully!"
}

# Delete configuration with enhanced validation
cmd_delete() {
    local name="$1"
    
    if [[ -z "$name" ]]; then
        log_error "Profile name is required!"
        echo "Usage: lam delete <profile_name>"
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
    
    local profile
    profile=$(echo "$config" | jq -r ".profiles[\"$name\"]" 2>/dev/null)
    
    if [[ "$profile" == "null" ]]; then
        log_error "Profile '$name' not found!"
        return 1
    fi
    
    echo -n "Are you sure you want to delete profile '$name'? (y/N): "
    local confirm
    if ! read -r confirm; then
        log_error "Failed to read confirmation"
        return 1
    fi
    
    if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
        log_info "Deletion cancelled."
        return 0
    fi
    
    config=$(echo "$config" | jq "del(.profiles[\"$name\"])") || {
        log_error "Failed to delete profile from configuration"
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
    
    log_success "Profile '$name' deleted successfully!"
}

# Test API connection with enhanced error handling
cmd_test() {
    if [[ -z "${LLM_CURRENT_PROFILE:-}" ]]; then
        log_error "No profile active. Use 'eval \"\$(lam use <profile>)\"' first."
        return 1
    fi
    
    log_info "Testing API connection for profile: $LLM_CURRENT_PROFILE"
    
    # Detect API type based on environment variables and test accordingly
    if [[ -n "${OPENAI_API_KEY:-}" && -n "${OPENAI_BASE_URL:-}" ]]; then
        log_info "Testing OpenAI-compatible API..."
        local model="${OPENAI_MODEL:-gpt-3.5-turbo}"
        
        local response
        if ! response=$(curl -s --max-time 30 --connect-timeout 10 \
             -H "Authorization: Bearer $OPENAI_API_KEY" \
             -H "Content-Type: application/json" \
             -d '{"model":"'"$model"'","messages":[{"role":"user","content":"Hello! Just testing the connection."}],"max_tokens":10}' \
             "${OPENAI_BASE_URL}/chat/completions" 2>/dev/null); then
            log_error "Failed to connect to OpenAI API"
            return 1
        fi
        
        if echo "$response" | jq -e '.choices[0].message.content' >/dev/null 2>&1; then
            log_success "OpenAI-compatible API connection successful!"
        else
            local error_msg
            error_msg=$(echo "$response" | jq -r '.error.message // "Unknown error"')
            log_error "API connection failed: $error_msg"
            return 1
        fi
    elif [[ -n "${ANTHROPIC_API_KEY:-}" && -n "${ANTHROPIC_BASE_URL:-}" ]]; then
        log_info "Testing Anthropic API..."
        local model="${ANTHROPIC_MODEL:-claude-3-haiku-20240307}"
        
        local response
        if ! response=$(curl -s --max-time 30 --connect-timeout 10 \
             -H "x-api-key: $ANTHROPIC_API_KEY" \
             -H "Content-Type: application/json" \
             -H "anthropic-version: 2023-06-01" \
             -d '{"model":"'"$model"'","max_tokens":10,"messages":[{"role":"user","content":"Hello! Just testing."}]}' \
             "${ANTHROPIC_BASE_URL}/v1/messages" 2>/dev/null); then
            log_error "Failed to connect to Anthropic API"
            return 1
        fi
        
        if echo "$response" | jq -e '.content[0].text' >/dev/null 2>&1; then
            log_success "Anthropic API connection successful!"
        else
            local error_msg
            error_msg=$(echo "$response" | jq -r '.error.message // "Unknown error"')
            log_error "API connection failed: $error_msg"
            return 1
        fi
    elif [[ -n "${API_KEY:-}" && -n "${BASE_URL:-}" ]]; then
        log_info "Testing custom API..."
        local model="${MODEL_NAME:-gpt-3.5-turbo}"
        
        local response
        if ! response=$(curl -s --max-time 30 --connect-timeout 10 \
             -H "Authorization: Bearer $API_KEY" \
             -H "Content-Type: application/json" \
             -d '{"model":"'"$model"'","messages":[{"role":"user","content":"Hello! Just testing."}],"max_tokens":10}' \
             "${BASE_URL}/chat/completions" 2>/dev/null); then
            log_error "Failed to connect to custom API"
            return 1
        fi
        
        if echo "$response" | jq -e '.choices[0].message.content' >/dev/null 2>&1; then
            log_success "Custom API connection successful!"
        else
            local error_msg
            error_msg=$(echo "$response" | jq -r '.error.message // "Unknown error"')
            log_error "API connection failed: $error_msg"
            return 1
        fi
    else
        log_error "No recognized API configuration found in environment"
        log_info "Make sure you have the required environment variables set:"
        log_info "  - For OpenAI: OPENAI_API_KEY, OPENAI_BASE_URL"
        log_info "  - For Anthropic: ANTHROPIC_API_KEY, ANTHROPIC_BASE_URL"
        log_info "  - For Custom: API_KEY, BASE_URL"
        return 1
    fi
}

# Backup profiles with enhanced error handling
cmd_backup() {
    local backup_file="${1:-lam-profiles-backup-$(date +%Y%m%d-%H%M%S).tar.gz}"
    
    # Validate backup filename
    if [[ ! "$backup_file" =~ ^[a-zA-Z0-9._-]+$ ]]; then
        log_error "Invalid backup filename. Use only alphanumeric characters, dots, dashes, and underscores."
        return 1
    fi
    
    if [[ -d "$CONFIG_DIR" ]]; then
        if tar -czf "$backup_file" -C "$(dirname "$CONFIG_DIR")" "$(basename "$CONFIG_DIR")/" 2>/dev/null; then
            log_success "Backup created: $backup_file"
            log_info "To restore: tar -xzf $backup_file -C $(dirname "$CONFIG_DIR")/"
        else
            log_error "Failed to create backup"
            return 1
        fi
    else
        log_error "No LAM configuration found"
        return 1
    fi
}

# Show LAM status and statistics
cmd_stats() {
    local config
    if ! config=$(get_session_config); then
        return 1
    fi
    
    echo "LAM Status & Statistics"
    echo "======================"
    echo
    
    # Basic info
    echo "Version: 3.1.0 (Security Hardened)"
    echo "Config Directory: $CONFIG_DIR"
    echo "Session Timeout: ${SESSION_TIMEOUT}s"
    echo
    
    # Profile statistics
    local profile_count
    profile_count=$(echo "$config" | jq -r '.profiles | length')
    echo "Total Profiles: $profile_count"
    
    if [[ "$profile_count" -gt 0 ]]; then
        echo
        echo "Profile Details:"
        echo "---------------"
        
        while IFS= read -r profile_name; do
            local profile
            profile=$(echo "$config" | jq -r ".profiles[\"$profile_name\"]")
            local env_count
            env_count=$(echo "$profile" | jq -r '.env_vars | length')
            local last_used
            last_used=$(echo "$profile" | jq -r '.last_used // "Never"')
            
            echo "• $profile_name: $env_count env vars, last used: $last_used"
        done <<< "$(echo "$config" | jq -r '.profiles | keys[]')"
    fi
    
    echo
    
    # Session info
    if is_session_valid; then
        echo "Session: Active"
        local session_age
        session_age=$(( $(date +%s) - $(stat -c %Y "$SESSION_FILE" 2>/dev/null || echo 0) ))
        echo "Session Age: ${session_age}s"
    else
        echo "Session: Expired/None"
    fi
    
    # Current profile
    if [[ -n "${LLM_CURRENT_PROFILE:-}" ]]; then
        echo "Active Profile: $LLM_CURRENT_PROFILE"
    else
        echo "Active Profile: None"
    fi
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
    if curl -sL "https://raw.githubusercontent.com/your-repo/lam/main/lam" -o "$temp_dir/lam"; then
        # Verify the downloaded file
        if [[ -f "$temp_dir/lam" ]] && [[ -s "$temp_dir/lam" ]] && head -1 "$temp_dir/lam" | grep -q "#!/bin/bash"; then
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
    echo "   • Visit: https://github.com/your-repo/lam"
    echo "   • Click 'Code' → 'Download ZIP' OR"
    echo "   • Clone: git clone https://github.com/your-repo/lam.git"
    echo
    log_info "2. Extract and navigate to the project directory:"
    echo "   • unzip lam-main.zip && cd lam-main  OR"
    echo "   • cd lam"
    echo
    log_info "3. Run the manual update script:"
    echo "   • ./version_update.sh"
    echo
    log_gray "The version_update.sh script will:"
    log_gray "• Find your current LAM installation"
    log_gray "• Backup the current version"
    log_gray "• Install the new version"
    log_gray "• Verify the installation"
}

# Uninstall LAM with enhanced cleanup
cmd_uninstall() {
    log_warning "This will completely remove LAM from your system!"
    echo
    echo "The following will be removed:"
    
    # Find installation location
    local current_script
    current_script=$(readlink -f "$0")
    local install_dir
    install_dir=$(dirname "$current_script")
    
    echo "• LAM executable: $current_script"
    
    # Check for user configuration
    if [[ -d "$CONFIG_DIR" ]]; then
        echo "• Configuration directory: $CONFIG_DIR"
        echo "  (contains encrypted API keys and profiles)"
    fi
    
    # Check for backup files
    if [[ -f "$current_script.backup" ]]; then
        echo "• Backup file: $current_script.backup"
    fi
    
    echo
    log_gray "⚠️  WARNING: This action cannot be undone!"
    log_gray "   Your encrypted API keys and profiles will be permanently deleted."
    echo
    
    echo -n "Are you sure you want to uninstall LAM? (type 'yes' to confirm): "
    local confirmation
    if ! read -r confirmation; then
        log_error "Failed to read confirmation"
        return 1
    fi
    
    if [[ "$confirmation" != "yes" ]]; then
        log_info "Uninstallation cancelled."
        return 0
    fi
    
    log_info "Uninstalling LAM..."
    
    # Remove configuration directory (includes session files) FIRST
    if [[ -d "$CONFIG_DIR" ]]; then
        if rm -rf "$CONFIG_DIR"; then
            log_success "Removed configuration directory and all session data"
        else
            log_error "Failed to remove configuration directory"
        fi
    fi
    
    # Remove backup if exists
    if [[ -f "$current_script.backup" ]]; then
        if rm -f "$current_script.backup"; then
            log_success "Removed backup file"
        else
            log_warning "Failed to remove backup file"
        fi
    fi
    
    # Show completion message BEFORE deleting executable
    echo
    log_success "LAM configuration and data have been removed!"
    log_info "You may want to remove $install_dir from your PATH if it was added specifically for LAM"
    echo
    
    # Create a self-deleting script to remove the executable after this script exits
    local cleanup_script="/tmp/lam_cleanup_$$"
    cat > "$cleanup_script" << 'EOF'
#!/bin/bash
sleep 1  # Wait for parent script to exit
if [[ -f "$1" ]]; then
    rm -f "$1"
fi
rm -f "$0"  # Remove this cleanup script
EOF
    chmod +x "$cleanup_script"
    
    log_info "Goodbye! 👋"
    
    # Start cleanup script in background and exit immediately
    "$cleanup_script" "$current_script" &
    exit 0
}