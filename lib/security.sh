#!/bin/bash

# LAM Security Module
# Password handling, encryption, and security functions

# Secure password reading function
get_master_password() {
    local prompt="${1:-Enter master password: }"
    local password
    
    # Ensure we're reading from terminal
    if [[ ! -t 0 ]]; then
        log_error "Password input requires interactive terminal"
        return 1
    fi
    
    # Disable echo and set up cleanup
    local old_settings
    old_settings=$(stty -g) || {
        log_error "Failed to save terminal settings"
        return 1
    }
    
    # Set up trap to restore settings
    trap 'stty "$old_settings" 2>/dev/null' RETURN
    
    # Disable echo
    stty -echo || {
        log_error "Failed to disable echo"
        return 1
    }
    
    echo -n "$prompt" >&2
    
    # Read password with timeout
    if ! read -r password; then
        echo >&2
        log_error "Failed to read password"
        return 1
    fi
    
    echo >&2  # Add newline after password input
    
    # Validate password length
    if [[ ${#password} -lt $MIN_PASSWORD_LENGTH ]]; then
        log_error "Password must be at least $MIN_PASSWORD_LENGTH characters long"
        return 1
    fi
    
    if [[ ${#password} -gt $MAX_PASSWORD_LENGTH ]]; then
        log_error "Password exceeds maximum length of $MAX_PASSWORD_LENGTH characters"
        return 1
    fi
    
    # Validate input
    if ! validate_input_length "$password" "$MAX_PASSWORD_LENGTH"; then
        return 1
    fi
    
    echo "$password"
}

# Encrypt data using AES-256-CBC
encrypt_data() {
    local data="$1"
    local password="$2"
    
    if [[ -z "$data" || -z "$password" ]]; then
        log_error "Data and password are required for encryption"
        return 1
    fi
    
    # Use OpenSSL for encryption with salt
    echo "$data" | openssl enc -aes-256-cbc -salt -pbkdf2 -iter 100000 -pass pass:"$password" -base64 2>/dev/null || {
        log_error "Failed to encrypt data"
        return 1
    }
}

# Decrypt data using AES-256-CBC
decrypt_data() {
    local encrypted_data="$1"
    local password="$2"
    
    if [[ -z "$encrypted_data" || -z "$password" ]]; then
        log_error "Encrypted data and password are required for decryption"
        return 1
    fi
    
    # Use OpenSSL for decryption
    echo "$encrypted_data" | openssl enc -aes-256-cbc -d -salt -pbkdf2 -iter 100000 -pass pass:"$password" -base64 2>/dev/null || {
        log_error "Failed to decrypt data - incorrect password or corrupted data"
        return 1
    }
}

# Get and verify master password
get_verified_master_password() {
    local password
    if ! password=$(get_master_password); then
        return 1
    fi
    
    # Test password by trying to decrypt config
    local test_decrypt
    if ! test_decrypt=$(decrypt_data "$(cat "$CONFIG_FILE")" "$password" 2>/dev/null); then
        log_error "Incorrect master password!"
        return 1
    fi
    
    echo "$password"
}

# Check if session is valid
is_session_valid() {
    [[ -f "$SESSION_FILE" ]] || return 1
    
    local session_time
    session_time=$(stat -c %Y "$SESSION_FILE" 2>/dev/null) || return 1
    
    local current_time
    current_time=$(date +%s)
    
    local time_diff=$((current_time - session_time))
    
    [[ $time_diff -lt $SESSION_TIMEOUT ]]
}

# Create session with atomic file operations
create_session() {
    local password="$1"
    
    if [[ -z "$password" ]]; then
        log_error "Password is required to create session"
        return 1
    fi
    
    # Create session directory if it doesn't exist
    local session_dir
    session_dir=$(dirname "$SESSION_FILE")
    if [[ ! -d "$session_dir" ]]; then
        if ! mkdir -p "$session_dir"; then
            log_error "Failed to create session directory"
            return 1
        fi
        chmod 700 "$session_dir"
    fi
    
    # Create temporary session file
    local temp_session
    if ! temp_session=$(create_temp_file); then
        return 1
    fi
    
    # Store encrypted password hash in session (for verification)
    local password_hash
    password_hash=$(echo -n "$password" | sha256sum | cut -d' ' -f1) || {
        log_error "Failed to create password hash"
        return 1
    }
    
    if ! echo "$password_hash" > "$temp_session"; then
        log_error "Failed to write session data"
        return 1
    fi
    
    # Atomic move to final location
    if ! mv "$temp_session" "$SESSION_FILE"; then
        log_error "Failed to create session file"
        return 1
    fi
    
    # Set secure permissions
    chmod 600 "$SESSION_FILE" || {
        log_error "Failed to set session file permissions"
        return 1
    }
    
    return 0
}