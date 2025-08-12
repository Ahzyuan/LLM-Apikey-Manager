#!/usr/bin/env bash

# LAM Security Module
# Password handling, encryption, and security functions

# ----------------------------------- Auth Verification -----------------------------------

# Store master password verification in database
init_auth_credential() {
    local password="$1"
    
    if [[ -z "$password" ]]; then
        log_error "Password is required for creating authentication credential"
        return 1
    fi
    
    # Generate random salt (32 bytes, base64 encoded)
    local salt
    if ! salt=$(openssl rand -base64 32 2>/dev/null); then
        log_error "Failed to generate random salt"
        return 1
    fi
    
    # Create SHA-256 hash of password + salt
    local password_hash
    if ! password_hash=$(echo -n "${password}${salt}" | openssl dgst -sha256 -binary | openssl base64 -A 2>/dev/null); then
        log_error "Failed to create password hash"
        return 1
    fi
    
    # Create verification data (known plaintext for encryption test)
    local verification_data="LAM_AUTH_VERIFICATION:${salt}:$(date -Iseconds)"
    
    # Encrypt verification data with master password
    local encrypted_info
    if ! encrypted_info=$(encrypt_data "$verification_data" "$password"); then
        log_error "Failed to encrypt verification data"
        return 1
    fi
    
    # Create integrity checksum (SHA-256 of all components)
    local checksum_input="${password_hash}|${encrypted_info}|${salt}"
    local checksum
    if ! checksum=$(echo -n "$checksum_input" | openssl dgst -sha256 -binary | openssl base64 -A 2>/dev/null); then
        log_error "Failed to create integrity checksum"
        return 1
    fi
        
    # Store in database using proper SQL escaping for base64 data
    local sql="
        INSERT OR REPLACE INTO auth_verification (id, password_hash, encrypted_info, salt, checksum)
        VALUES (
            1, 
            '$(echo "$password_hash" | sed "s/'/''/g")', 
            '$(echo "$encrypted_info" | sed "s/'/''/g")', 
            '$(echo "$salt" | sed "s/'/''/g")', 
            '$(echo "$checksum" | sed "s/'/''/g")'
        );
    "
    
    if ! execute_sql "$sql"; then
        log_error "Failed to store password verification in database"
        return 1
    fi
    
    return 0
}

# Verify master password by decrypting existing profile data
verify_profile_decryption() {
    local password="$1"

    if [[ -z "$password" ]]; then
        log_error "Password is required to perform profile decryption verification"
        return 1
    fi
    
    # Get random profile with environment variables
    local random_env
    if ! random_env=$(execute_sql "
        SELECT value FROM profile_env_vars 
        ORDER BY RANDOM() 
        LIMIT 1;" true 2>/dev/null
    ); then
        log_gray "[Decrypt Error] Failed to query profile data for verification"
        return 1
    fi
    
    if [[ -z "$random_env" ]]; then
        log_gray "[Decrypt Warning] No profiles found for password verification"
        log_gray "[Decrypt Warning] Assuming password is correct (no encrypted data to test against)"
        return 0
    fi
    
    # Try to decrypt the environment variable
    local decrypted_value
    if ! decrypted_value=$(decrypt_data "$random_env" "$password" 2>/dev/null); then
        log_gray "[Decrypt Error] Password cannot decrypt existing data"
        return 1
    fi
    
    # Basic sanity check on decrypted data (should not be empty and should be reasonable)
    if [[ -z "$decrypted_value" ]]; then
        log_gray "[Decrypt Error] Password verification failed - decrypted data is empty"
        return 1
    fi
    
    return 0
}

# Verify authentication credential
verify_auth_credential() {
    local password="$1"
    local stored_hash stored_encrypted stored_salt 
    local stored_checksum
    
    if [[ -z "$password" ]]; then
        log_error "Password is required to perform authentication verification"
        return 1
    fi
    
    if ! execute_sql "SELECT COUNT(*) FROM auth_verification WHERE id = 1;" true | grep -q "1" 2>/dev/null; then
        log_gray "[Auth Error] Authentication credential data is missing!"
        return 1
    fi

    if ! stored_hash=$(execute_sql "SELECT password_hash FROM auth_verification WHERE id = 1;" true 2>/dev/null); then
        log_gray "[Auth Error] Failed to retrieve password hash from database"
        return 1
    fi
    
    if ! stored_encrypted=$(execute_sql "SELECT encrypted_info FROM auth_verification WHERE id = 1;" true 2>/dev/null); then
        log_gray "[Auth Error] Failed to retrieve encrypted verification from database"
        return 1
    fi
    
    if ! stored_salt=$(execute_sql "SELECT salt FROM auth_verification WHERE id = 1;" true 2>/dev/null); then
        log_gray "[Auth Error] Failed to retrieve salt from database"
        return 1
    fi
    
    if ! stored_checksum=$(execute_sql "SELECT checksum FROM auth_verification WHERE id = 1;" true 2>/dev/null); then
        log_gray "[Auth Error] Failed to retrieve checksum from database"
        return 1
    fi
    
    # Check if any field is empty
    if [[ -z "$stored_hash" || -z "$stored_encrypted" || -z "$stored_salt" || -z "$stored_checksum" ]]; then
        log_gray "[Auth Error] Authentication credential data is incomplete!"
        return 1
    fi

    # Verify integrity checksum first
    local checksum_input="${stored_hash}|${stored_encrypted}|${stored_salt}"
    local actual_checksum
    if ! actual_checksum=$(
        echo -n "$checksum_input" | openssl dgst -sha256 -binary | openssl base64 -A 2>/dev/null
    ); then
        log_gray "[Auth Error] Failed to calculate integrity checksum"
        return 1
    fi
    
    if [[ "$actual_checksum" != "$stored_checksum" ]]; then
        log_gray "[Auth Error] Authentication credential has been tampered with!"
        return 1
    fi

    # Verify password hash
    local actual_hash
    if ! actual_hash=$(
        echo -n "${password}${stored_salt}" | openssl dgst -sha256 -binary | openssl base64 -A 2>/dev/null
    ); then
        log_gray "[Auth Error] Failed to create password hash for verification"
        return 1
    fi
    
    if [[ "$actual_hash" != "$stored_hash" ]]; then
        log_gray "[Auth Error] Master password hash vefication failed!"
        return 1
    fi
    
    # Decrypt and verify the encrypted verification data
    local decrypted_info
    if ! decrypted_info=$(decrypt_data "$stored_encrypted" "$password" 2>/dev/null); then
        log_gray "[Auth Error] Failed to decrypt verification data!"
        return 1
    fi
    
    if [[ ! "$decrypted_info" =~ ^LAM_AUTH_VERIFICATION: ]]; then
        log_gray "[Auth Error] Password verification failed - invalid verification data!"
        return 1
    fi
    
    return 0
}

# Authenticate user identity when master password is forgotten
authenticate_user_passwd() {
    local current_user
    current_user=$(whoami)
    
    log_info "Authenticating user: ${PURPLE}$current_user${NC}"
    
    # Method 1: Try sudo authentication (most common)
    if command -v sudo >/dev/null 2>&1; then        
        if sudo -v 2>/dev/null; then
            return 0
        else
            log_warning "Sudo authentication failed"
        fi
    fi
    echo
    
    # Method 2: Try su authentication as fallback
    if command -v su >/dev/null 2>&1; then
        log_info "Attempting alternative authentication method..."
        echo -e "Please enter the password of user ${PURPLE}$current_user${NC}:"
        
        # Use su to verify user credentials
        if echo "exit 0" | su "$current_user" -c "exit 0" 2>/dev/null; then
            return 0
        else
            log_warning "Alternative authentication failed"
        fi
    fi
    echo
    
    # Method 3: File-based verification (create a file that requires user permissions)
    log_info "Attempting file-based authentication verification..."
    
    local test_file="$CONFIG_DIR/.auth_test_$$"
    touch "$test_file" 2>/dev/null
    
    # Verify the file was created by the current user
    if [[ -f "$test_file" && -O "$test_file" ]]; then
        rm -f "$test_file" 2>/dev/null
        return 0
    fi
    echo 
    
    log_error "User authentication failed"
    return 1
}

# ----------------------------------- Password Retrieval ----------------------------------- 

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
    
    echo "$(sanitize_input $password)"
}

# Get and verify master password
get_verified_master_password() {
    local password
    local prompt="${1:-Enter master password: }"
    local credential_auth_pass=false
    local profile_decrypt_pass=false

    # Check if database exists
    check_initialization || return 1

    # Get master password and perform authentication verification
    for i in {1..4}; do
        if ! password=$(get_master_password "$prompt"); then
            return 1
        else
            [[ -n "$password" ]] || {
                log_error "Password is required to perform authentication verification"
                return 1
            }
        fi

        # Verify authentication credential
        if verify_auth_credential "$password" 2>/dev/null; then
            credential_auth_pass=true
        else 
            credential_auth_pass=false
            echo
        fi
        
        # Verify profile decryption
        if verify_profile_decryption "$password" 2>/dev/null; then
            profile_decrypt_pass=true
        else 
            profile_decrypt_pass=false
            echo
        fi
        
        # password is valid only when both checks passed
        if [[ $credential_auth_pass == true && $profile_decrypt_pass == true ]]; then
            break
        fi
        prompt="${RED}$i/3 | Invalid password! Please try again: ${NC}"
    done

    if [[ $credential_auth_pass == false || $profile_decrypt_pass == false ]]; then 
        echo '------------------------------------------------------------------------' >&2
    fi

    if [ $credential_auth_pass = false ] && [ $profile_decrypt_pass = true ]; then
        # no profile and authentication credential are valid, then password is wrong
        if [[ $(execute_sql "SELECT COUNT(*) FROM profile_env_vars;" true) -eq 0 ]]; then
            log_error "Password is wrong, or your authentication credential is ${RED}deleted or has been tampered with!"
            log_info "Now that no profile detected, if you forget your master password, you can now safely reset it by running ${PURPLE}lam init${NC}."
            exit 1
        fi

        log_info "The authentication credential is ${RED}deleted or has been tampered with!${NC}"
        log_info "Fortunately, the profile data is still intact."
        log_info "For security concerns, LAM will help you recover the authentication credential."
        log_info "This operation will repair broken authentication credential automatically and has no impact on your future using."
        
        echo -en "${BLUE}Sure to proceed?${NC} (y/N): " >&2
        local sure_repair
        if ! read -r sure_repair; then
            log_error "Failed to read confirmation"
            return 1
        fi
        
        if [[ $sure_repair == [Yy] ]]; then
            init_auth_credential "$password" || return 1
            log_success "Repair successfully!"
            echo >&2
        else
            log_info "Operation cancelled"
            return 0
        fi

    elif [ $profile_decrypt_pass = false ]; then
        # password pass auth verify but fail to decrypt profile
        if [ $credential_auth_pass = true ]; then
            log_error "${RED}The encrypted profile content has been tampered with!${NC}"
            log_error "In this case, all profiles data are broken and cannot be accessed."
            log_error "Therefore, LAM suggest to remove all profiles and perform a re-initialization."

            echo -en "${RED}Sure to remove all existing profiles?${NC} (y/N): " >&2
            local sure_remove
            if ! read -r sure_remove; then
                log_error "Failed to read confirmation"
                return 1
            fi

            if [[ $sure_remove == [Yy] ]]; then 
                clear_all_profiles || return 1
                log_success "Profiles removed successfully!"
                echo >&2
                log_info "Since no profiles are left, current operation will be aborted."
                log_info "Please run ${PURPLE}lam add <profile-name>${NC} to add a profile."
                log_info "Or run ${PURPLE}lam backup load${NC} to recover your previous profiles if any backup exists."
                exit 1
            fi            

        # both auth verification and decryption verification failed
        else 
            log_info "Authentication failed! This may be caused by:"
            log_info "1. You have made a typo when entering the password; ${GRAY}(most likely)${NC}"
            log_info "2. You have forgotten your master password;"
            log_info "3. Both ${RED}authentication credential${NC} and ${RED}encrypted profile content${NC} are deleted or has been tampered with;"
            echo >&2
            echo 'Now, you have several options to handle this case:' >&2
            log_gray "1): try your master password again"
            log_gray "2): remove all data(cause wrong) and reset LAM ${RED}(dangerous operation)${NC}"
            
            local choice
            echo -n "Enter your choice (1/2): " >&2
            if ! read -r choice; then
                log_error "Failed to read choice"
                return 1
            fi

            case "${choice}" in 
                "1")
                    exit 1
                    ;;
                "2")
                    echo >&2
                    log_info "Dangerous operation!"
                    log_info "Please type ${PURPLE}'proceed to clear and re-init'${NC} to continue: "
                    
                    local sure_reset
                    if ! read -r sure_reset; then
                        log_error "Failed to read input"
                        return 1
                    fi
                    
                    if [[ "${sure_reset,,}" == "proceed to clear and re-init" ]]; then 
                        rm -rf "BACKUP_DIR" && rm -rf "$DB_FILE" 2>/dev/null || {
                            log_error "Failed to clear profiles"
                            log_info "You can manually delete the path ${PURPLE}$DB_FILE${NC} and ${PURPLE}${BACKUP_DIR}${NC}."
                            log_info "Then re-init LAM by running ${PURPLE}'lam init'${NC}"
                            exit 1
                        }
                        log_success "Cleared all profiles"
                        echo >&2
                        log_info "Since no profiles are left, current operation will be aborted."
                        log_info "Please run ${PURPLE}lam init${NC} to re-init LAM."
                    else
                        log_info "Operation cancelled."
                        exit 1
                    fi
                    ;;
                *)
                    log_error "Unknown choice: $choice"
                    log_info "Operation cancelled."
                    exit 1
                    ;;
            esac
        fi    
    fi
    
    # Create a session for successful password verification
    if ! create_session "$password"; then
        log_warning "Password verification passed, but failed to create session"
    fi
    
    echo "$(sanitize_input $password)"
}

# ----------------------------------- En/Decrypt -----------------------------------

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

# ----------------------------------- Session Mangement -----------------------------------

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

# ------------------------------------ Renew Password -----------------------------------

reencrypt_profile() { 
    local profile_name="$1"
    local old_password="$2"
    local new_password="$3"

    if [[ -z "$profile_name" ]]; then
        log_error "Profile name is required"
        return 1
    fi

    profile_name="$(printf '%s' "$profile_name" | sed "s/'/''/g")"

    # Get profile ID
    local profile_id
    profile_id=$(
        execute_sql "SELECT id FROM profiles WHERE name = '$profile_name';" true
    ) 2>/dev/null
    
    if [[ -z "$profile_id" ]]; then
        log_warning "Failed to get profile ID for profile ${PURPLE}'$profile_name'${NC}"
        return 1
    fi
    
    # Get all environment variables for this profile
    local env_vars_data
    env_vars_data=$(execute_sql "
        SELECT key, value
        FROM profile_env_vars 
        WHERE profile_id = $profile_id;
    " true)
    
    if [[ -z "$env_vars_data" ]]; then
        log_info "No environment variables found for profile ${PURPLE}'$profile_name'${NC}. Skipping..."
        return 0
    fi

    # Process each environment variable
    while IFS='|' read -r key encrypted_value; do
        if [[ -n "$key" && -n "$encrypted_value" ]]; then
            # Skip base URL variables (they are not encrypted)
            if [[ "$key" =~ .*[Bb][Aa][Ss][Ee].*[Uu][Rr][Ll].* ]]; then
                continue
            fi
            
            # Decrypt with old password
            local decrypted_value
            if ! decrypted_value=$(decrypt_data "$encrypted_value" "$old_password" 2>/dev/null); then
                log_error "Failed to decrypt ${PURPLE}'$key'${NC} with old password in profile ${PURPLE}'$profile_name'${NC}"
                return 1
            fi
            
            # Re-encrypt with new password
            local new_encrypted_value
            if ! new_encrypted_value=$(encrypt_data "$decrypted_value" "$new_password" 2>/dev/null); then
                log_error "Failed to re-encrypt ${PURPLE}'$key'${NC} in profile ${PURPLE}'$profile_name'${NC}"
                return 1
            fi
            
            # Update in database
            local escaped_key escaped_value
            escaped_key=$(printf '%s' "$key" | sed "s/'/''/g")
            escaped_value=$(printf '%s' "$new_encrypted_value" | sed "s/'/''/g")
            
            local update_sql="
                UPDATE profile_env_vars 
                SET value = '$escaped_value'
                WHERE profile_id = $profile_id AND key = '$escaped_key';
            "
            
            if ! execute_sql "$update_sql" 2>/dev/null; then
                log_error "Failed to update ${PURPLE}'$key'${NC} in profile ${PURPLE}'$profile_name'${NC}"
                return 1
            fi
        fi
    done <<< "$env_vars_data"
}

reencrypt_backup() {
    local backup_file="$1"
    local old_password="$2"
    local new_password="$3"

    local backup_name
    backup_name=$(basename "$backup_file")
    
    # Create temporary directory for backup processing
    local temp_backup_dir
    if ! temp_backup_dir=$(mktemp -d); then
        log_error "Failed to create temp directory for backup: $backup_name"
        return 1
    fi
    TEMP_DIRS+=("$temp_backup_dir")
    
    # Extract backup
    if ! tar -xzf "$backup_file" -C "$temp_backup_dir" 2>/dev/null; then
        log_error "Failed to extract backup: $backup_name"
        return 1
    fi
    
    local backup_db_file="$temp_backup_dir/lam-config/profiles.db"
    if [[ ! -f "$backup_db_file" ]]; then
        log_info "No database found in backup: $backup_name. Skipping..."
        return 1
    fi
    
    # Process environment variables in backup database
    local backup_env_vars
    backup_env_vars=$(sqlite3 "$backup_db_file" "
        SELECT p.name, pev.key, pev.value, pev.id
        FROM profiles p 
        JOIN profile_env_vars pev ON p.id = pev.profile_id;
    " 2>/dev/null)
    
    if [[ -n "$backup_env_vars" ]]; then
        local backup_vars_updated=0
        
        while IFS='|' read -r profile_name key encrypted_value env_var_id; do
            if [[ -n "$key" && -n "$encrypted_value" ]]; then
                # Skip base URL variables
                if [[ "$key" =~ .*[Bb][Aa][Ss][Ee].*[Uu][Rr][Ll].* ]]; then
                    continue
                fi
                
                # Decrypt with old password
                local decrypted_value
                if ! decrypted_value=$(decrypt_data "$encrypted_value" "$old_password" 2>/dev/null); then
                    log_error "Failed to decrypt $key in backup $backup_name"
                    return 1
                fi
                
                # Re-encrypt with new password
                local new_encrypted_value
                if ! new_encrypted_value=$(encrypt_data "$decrypted_value" "$new_password" 2>/dev/null); then
                    log_error "Failed to re-encrypt $key in backup $backup_name"
                    return 1
                fi
                
                # Update in backup database
                local escaped_value
                escaped_value=$(printf '%s' "$new_encrypted_value" | sed "s/'/''/g")
                
                if ! sqlite3 "$backup_db_file" "
                    UPDATE profile_env_vars 
                    SET value = '$escaped_value'
                    WHERE id = $env_var_id;
                " 2>/dev/null; then
                    log_error "Failed to update $key in backup $backup_name"
                    return 1
                fi
                
                ((backup_vars_updated++))
            fi
        done <<< "$backup_env_vars"
        
        if [[ $backup_vars_updated -gt 0 ]]; then
            if ! tar -czf "$backup_file" -C "$temp_backup_dir" "lam-config" 2>/dev/null; then
                log_error "Failed to update backup archive: $backup_name"
                return 1
            fi
        else
            log_info "No encrypted variables found in backup: $backup_name. Skipping..."
        fi
    else
        log_info "No environment variables found in backup: $backup_name. Skipping..."
    fi
}

# Renew master password while preserving all encrypted data
renew_master_password() {
    local old_password="$1"
    
    if [[ -z "$old_password" ]]; then
        log_error "Current password is required for password renewal"
        return 1
    fi
        
    # Get new password
    local new_password confirm_password
    if ! new_password=$(get_master_password "Enter new master password: " true); then
        log_error "Failed to get new master password"
        return 1
    fi
    
    if ! confirm_password=$(get_master_password "Confirm new master password: "); then
        log_error "Failed to confirm new master password"
        return 1
    fi
    
    if [[ "$new_password" != "$confirm_password" ]]; then
        log_error "Passwords do not match!"
        return 1
    fi
    
    if [[ "$old_password" == "$new_password" ]]; then
        log_info "New password is the same as the old one! Operation cancelled."
        return 0
    fi
    echo
        
    # Step 2: Re-encrypt all environment variables in profiles
    local profile_names
    profile_names=$(get_profile_names)

    log_info "Re-encrypting profiles..."
    
    if [[ -z "$profile_names" ]]; then
        log_info "No profiles need to re-encrypted"
    else
        local all_profile_reencrypted=true
        while IFS= read -r profile_name; do
            if ! reencrypt_profile "$profile_name" "$old_password" "$new_password";then
                all_profile_reencrypted=false
                continue
            fi
        done <<< "$profile_names"
        
        if $all_profile_reencrypted; then
            log_success "Re-encrypt profiles successfully"
        else
            log_warning "During the re-encrypt process, some profiles had errors shown above."
            log_warning "These profiles might be broken and can not be used any more. Consider deleting them by ${PURPLE}lam edit${NC}."
        fi
        echo '------------------------------------------------------------'
        echo
    fi
    
    # Step 3: Re-encrypt environment variables in all backup files
    log_info "Re-encrypting backup files..."

    if [[ -d "$BACKUP_DIR" ]]; then
        local backup_files=()
        for file in "$BACKUP_DIR"/*.tar.gz; do
            if [[ -f "$file" ]]; then
                backup_files+=("$file")
            fi
        done
        
        if [[ ${#backup_files[@]} -gt 0 ]]; then
            local all_backup_reencrypted=true
            for backup_file in "${backup_files[@]}"; do
                if ! reencrypt_backup "$backup_file" "$old_password" "$new_password"; then
                    all_backup_reencrypted=false
                    continue
                fi
            done
            
            if $all_backup_reencrypted; then
                log_success "Re-encrypt backups successfully"
            else
                log_warning "During the re-encrypt process, some backups had errors shown above."
                log_warning "These backups might be broken and can not be used any more. Consider deleting them by ${PURPLE}lam backup delete${NC}."
            fi
        else
            log_info "No backup files found. Skipping..."
        fi
    else
        log_info "No backup directory found. Skipping..."
    fi
    echo '------------------------------------------------------------'
    echo
    
    if [[ $all_backup_reencrypted == false && $all_profile_reencrypted == false ]]; then
        log_error "Password renewal failed."
        return 1
    fi

    # Step 4: Update authentication credential with new password
    init_auth_credential "$new_password" || return 1

    log_success "Master password renewal completed successfully!"
    log_success "Your new master password is now active and the old password is no longer valid"

    # Create a new session with the new password
    if ! create_session "$new_password"; then
        log_warning "Password renewal completed, but failed to create new session"
    fi
    
    return 0
}
