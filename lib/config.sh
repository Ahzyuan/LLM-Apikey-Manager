#!/bin/bash

# LAM Configuration Module
# Configuration management, loading, saving, and validation

# Initialize configuration directory
init_config_dir() {
    if [[ ! -d "$CONFIG_DIR" ]]; then
        if ! mkdir -p "$CONFIG_DIR"; then
            log_error "Failed to create config directory: $CONFIG_DIR"
            return 1
        fi
        
        # Set secure permissions
        chmod 700 "$CONFIG_DIR" || {
            log_error "Failed to set config directory permissions"
            return 1
        }
    fi
    
    return 0
}

# Validate configuration structure
validate_config() {
    local config="$1"
    
    # Check if it's valid JSON
    if ! echo "$config" | jq empty 2>/dev/null; then
        log_error "Configuration is not valid JSON"
        return 1
    fi
    
    # Check if it has the required structure
    if ! echo "$config" | jq -e '.profiles' >/dev/null 2>&1; then
        log_error "Configuration missing 'profiles' section"
        return 1
    fi
    
    return 0
}

# Get configuration from session or decrypt from file
get_session_config() {
    # Try to get from session first
    if is_session_valid; then
        local cached_config="$CONFIG_DIR/.cached_config"
        if [[ -f "$cached_config" ]]; then
            cat "$cached_config"
            return 0
        fi
    fi
    
    # Need to decrypt from file
    local password
    if ! password=$(get_verified_master_password); then
        return 1
    fi
    
    local config
    if ! config=$(decrypt_data "$(cat "$CONFIG_FILE")" "$password"); then
        return 1
    fi
    
    # Validate configuration
    if ! validate_config "$config"; then
        return 1
    fi
    
    # Cache the config and create session
    local cached_config="$CONFIG_DIR/.cached_config"
    if ! echo "$config" > "$cached_config"; then
        log_warning "Failed to cache configuration"
    else
        chmod 600 "$cached_config"
    fi
    
    if ! create_session "$password"; then
        log_warning "Failed to create session"
    fi
    
    echo "$config"
}

# Save config with validation and atomic operations
save_session_config() {
    local config="$1"
    local password="$2"
    
    if [[ -z "$config" || -z "$password" ]]; then
        log_error "Configuration and password are required"
        return 1
    fi
    
    # Validate configuration before saving
    if ! validate_config "$config"; then
        return 1
    fi
    
    # Create temporary file for atomic operation
    local temp_file
    if ! temp_file=$(create_temp_file); then
        return 1
    fi
    
    # Encrypt and save to temporary file
    local encrypted_config
    if ! encrypted_config=$(encrypt_data "$config" "$password"); then
        log_error "Failed to encrypt configuration"
        return 1
    fi
    
    if ! echo "$encrypted_config" > "$temp_file"; then
        log_error "Failed to write encrypted configuration"
        return 1
    fi
    
    # Atomic move to final location
    if ! mv "$temp_file" "$CONFIG_FILE"; then
        log_error "Failed to save configuration file"
        return 1
    fi
    
    # Set secure permissions
    chmod 600 "$CONFIG_FILE" || {
        log_error "Failed to set configuration file permissions"
        return 1
    }
    
    # Update cached config
    local cached_config="$CONFIG_DIR/.cached_config"
    if ! echo "$config" > "$cached_config"; then
        log_warning "Failed to update cached configuration"
    else
        chmod 600 "$cached_config"
    fi
    
    # Update session
    if ! create_session "$password"; then
        log_warning "Failed to update session"
    fi
    
    return 0
}

# Load configuration (legacy function for compatibility)
load_config() {
    local password="$1"
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "Configuration file not found: $CONFIG_FILE"
        return 1
    fi
    
    if [[ -z "$password" ]]; then
        log_error "Password is required to load configuration"
        return 1
    fi
    
    local config
    if ! config=$(decrypt_data "$(cat "$CONFIG_FILE")" "$password"); then
        return 1
    fi
    
    if ! validate_config "$config"; then
        return 1
    fi
    
    echo "$config"
}

# Save configuration (legacy function for compatibility)
save_config() {
    local config="$1"
    local password="$2"
    
    save_session_config "$config" "$password"
}