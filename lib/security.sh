#!/usr/bin/env bash

# LAM Security Module
# Password handling, encryption, and security functions

# Secure password reading function
get_master_password() {
    local prompt="${1:-Enter master password: }"
    local password
    local length_verified="${2:-false}"
    
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
    
    echo -en "$prompt" >&2
    
    # Read password with timeout
    if ! read -r password; then
        echo >&2
        log_error "Failed to read password"
        return 1
    fi
    
    echo >&2  # Add newline after password input
    
    # Validate password length
    if [[ "$length_verified" == "true" || "$length_verified" == "1" ]]; then
        if [[ ${#password} -lt $MIN_PASSWORD_LENGTH ]]; then
            log_error "Password must be at least $MIN_PASSWORD_LENGTH characters long"
            return 1
        fi
        
        if [[ ${#password} -gt $MAX_PASSWORD_LENGTH ]]; then
            log_error "Password exceeds maximum length of $MAX_PASSWORD_LENGTH characters"
            return 1
        fi
    fi
    
    echo "$password"
}

# Get and verify master password
get_verified_master_password() {
    local password
    local prompt="${1:-Enter master password: }"
    if ! password=$(get_master_password "$prompt"); then
        return 1
    fi
    
    # Test password by trying to decrypt verification file
    local verification_file="$CONFIG_DIR/.auth"
    local db_file="$CONFIG_DIR/profiles.db"
    
    # If verification file exists, use it to verify password
    if [[ -f "$verification_file" ]]; then
        local test_decrypt
        if ! test_decrypt=$(decrypt_data "$(cat "$verification_file")" "$password" 2>/dev/null); then
            log_error "Incorrect master password!"
            return 1
        fi
        
        # Verify the decrypted content is correct
        if [[ "$test_decrypt" != "LAM_AUTH_CHECK" ]]; then
            log_error "Password verification failed!"
            return 1
        fi
    # If only SQLite database exists without verification file, this is an error
    elif [[ -f "$db_file" ]]; then
        log_error "Password verification file missing!"
        log_info "This may indicate a corrupted installation."
        log_info "Please run 'lam init' to reinitialize LAM."
        return 1
    else
        log_error "No LAM configuration found!"
        log_info "Please run 'lam init' first to initialize LAM."
        return 1
    fi
    
    # Create a session for successful password verification
    if ! create_session "$password"; then
        log_warning "Failed to create session, but password verification succeeded"
    fi
    
    echo "$password"
}

# Create password verification file for SQLite setups
create_auth_file() {
    local password="$1"
    
    if [[ -z "$password" ]]; then
        log_error "Password is required for verification file creation"
        return 1
    fi
            
    # Encrypt a simple verification string with the password
    local encrypted_verification
    if ! encrypted_verification=$(encrypt_data "LAM_AUTH_CHECK" "$password"); then
        log_error "Failed to create password verification"
        return 1
    fi
    
    # Create password authentication file
    if ! echo "$encrypted_verification" > "$AUTH_FILE"; then
        log_error "Failed to save password verification file"
        return 1
    fi
    
    chmod 600 "$AUTH_FILE" || {
        log_error "Failed to set verification file permissions"
        return 1
    }
    
    return 0
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