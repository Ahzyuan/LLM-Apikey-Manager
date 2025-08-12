#!/usr/bin/env bash

# LAM Configuration Module - SQLite Backend
# Database management, CRUD operations for profiles and environment variables

# ----------------------------------- Database Setup -----------------------------------

# Create configuration directory
init_config_dir() {

    if [[ ! -d "$CONFIG_DIR" ]]; then
        if ! mkdir -p "$CONFIG_DIR"; then
            log_error "Failed to create config directory: $CONFIG_DIR"
            log_info "You can manually create it by running: mkdir -p $CONFIG_DIR"
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

# Initialize database with schema
init_database() {    
    # Create database and tables
    local schema="
        -- Profiles table
        CREATE TABLE IF NOT EXISTS profiles (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT UNIQUE NOT NULL,
            model_name TEXT NOT NULL,
            description TEXT DEFAULT 'No description provided',
            created_at TEXT NOT NULL DEFAULT (datetime('now')),
            last_used TEXT,
            updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        );

        -- Environment variables table (normalized design)
        CREATE TABLE IF NOT EXISTS profile_env_vars (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            profile_id INTEGER NOT NULL,
            key TEXT NOT NULL,
            value TEXT NOT NULL,
            FOREIGN KEY (profile_id) REFERENCES profiles (id) ON DELETE CASCADE,
            UNIQUE (profile_id, key)
        );

        -- Metadata table
        CREATE TABLE IF NOT EXISTS metadata (
            key TEXT PRIMARY KEY,
            value TEXT NOT NULL
        );
        
        -- Master password verification table (tamper-resistant)
        CREATE TABLE IF NOT EXISTS auth_verification (
            id INTEGER PRIMARY KEY CHECK (id = 1), -- Only allow one row
            password_hash TEXT NOT NULL,           -- SHA-256 hash of master password
            encrypted_info TEXT NOT NULL,  -- Self-encrypted verification data
            salt TEXT NOT NULL,                   -- Random salt for additional security
            checksum TEXT NOT NULL,               -- Integrity checksum
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
        );

        -- Indexes for performance
        CREATE INDEX IF NOT EXISTS idx_profiles_name ON profiles(name);
        CREATE INDEX IF NOT EXISTS idx_env_vars_profile_id ON profile_env_vars(profile_id);
        CREATE INDEX IF NOT EXISTS idx_env_vars_key ON profile_env_vars(key);
        
        -- Triggers to update updated_at timestamp
        CREATE TRIGGER IF NOT EXISTS update_profiles_timestamp 
        AFTER UPDATE ON profiles
        BEGIN
            UPDATE profiles SET updated_at = datetime('now') WHERE id = NEW.id;
        END;
    "
    
    if ! execute_sql "$schema"; then
        log_error "Failed to initialize database schema"
        return 1
    fi
    
    # Set initial metadata
    set_metadata "version" "$(get_version_info | cut -d'|' -f1)"
    set_metadata "created" "$(date -Iseconds)"
    
    # Set secure permissions on database file
    chmod 600 "$DB_FILE" || {
        log_error "Failed to set database file permissions"
        return 1
    }
    
    return 0
}

# ------------------------------------- SQL Execution -------------------------------------

# Execute SQL command with optional result output
# Usage: execute_sql "SQL_COMMAND" [return_results]
# - If return_results is "true" or "1", returns query results
# - Otherwise, executes command silently and returns exit code
execute_sql() {
    local sql="$1"
    local return_results="${2:-false}"
    
    if [[ -z "$sql" ]]; then
        log_error "SQL command is required"
        return 1
    fi
    
    if [[ "$return_results" == "true" || "$return_results" == "1" ]]; then
        # Return results for SELECT queries
        sqlite3 "$DB_FILE" "$sql" 2>/dev/null || {
            log_error "Failed to execute SQL query"
            return 1
        }
    else
        # Execute without output for INSERT/UPDATE/DELETE
        if ! sqlite3 "$DB_FILE" "$sql" 2>/dev/null; then
            log_error "Failed to execute SQL command"
            return 1
        fi
        return 0
    fi
}


# -------------------------------- Profile CRUD Operations --------------------------------

# Check if profile exists
profile_exists() {
    local name="$1"
    
    if [[ -z "$name" ]]; then
        log_error "Profile name is required"
        return 1
    fi
    
    local count
    count=$(execute_sql "SELECT COUNT(*) FROM profiles WHERE name = '$name';" true)
    
    [[ "$count" -gt 0 ]]
}

# Create new profile
create_profile() {
    local name="$1"
    local model_name="$2"
    local description="$3"
    local env_vars_json="$4"
    
    if [[ -z "$name" || -z "$model_name" ]]; then
        log_error "Profile name and model name are required"
        return 1
    fi
    
    # Escape single quotes in SQL
    name=$(printf '%s' "$name" | sed "s/'/''/g")
    model_name=$(printf '%s' "$model_name" | sed "s/'/''/g")
    description=$(printf '%s' "${description:-No description provided}" | sed "s/'/''/g")
    
    # Insert profile
    local profile_sql="
        INSERT INTO profiles (name, model_name, description, created_at)
        VALUES ('$name', '$model_name', '$description', datetime('now', 'localtime'));
    "
    
    if ! execute_sql "$profile_sql" 2>/dev/null; then
        log_error "Failed to dump profile to database"
        return 1
    fi
    
    # Get profile ID
    local profile_id
    profile_id=$(execute_sql "SELECT id FROM profiles WHERE name = '$name';" true)
    
    if [[ -z "$profile_id" ]]; then
        log_error "Failed to retrieve profile ID"
        return 1
    fi
    
    # Insert environment variables if any
    if [[ -n "$env_vars_json" && "$env_vars_json" != "{}" ]]; then
        local keys values
        
        if ! keys=$(echo "$env_vars_json" | jq -r 'keys[]' 2>/dev/null); then
            log_error "Failed to parse environment variables JSON"
            return 1
        fi
        
        while IFS= read -r key; do
            if [[ -n "$key" ]]; then
                local value
                if ! value=$(echo "$env_vars_json" | jq -r --arg k "$key" '.[$k]' 2>/dev/null); then
                    log_error "Failed to extract value for key: $key"
                    return 1
                fi
                
                # Escape single quotes for SQL
                local escaped_key escaped_value
                escaped_key=$(printf '%s' "$key" | sed "s/'/''/g")
                escaped_value=$(printf '%s' "$value" | sed "s/'/''/g")
                    
                    local env_sql="
                        INSERT INTO profile_env_vars (profile_id, key, value)
                    VALUES ($profile_id, '$escaped_key', '$escaped_value');
                    "
                    
                if ! execute_sql "$env_sql" 2>/dev/null; then
                    log_error "Failed to insert environment variable: $key"
                    return 1
                fi
            fi
        done <<< "$keys"
    fi
    return 0
}

# Get profile by name (returns JSON format for compatibility)
get_profile() {
    local name="$1"
    
    if [[ -z "$name" ]]; then
        log_error "Profile name is required"
        return 1
    fi

    if ! profile_exists "$name"; then
        log_error "Profile '$name' does not exist"
        return 1
    fi
    
    # Escape single quotes
    name=$(printf '%s' "$name" | sed "s/'/''/g")
    
    # Get profile data
    local profile_data
    profile_data=$(execute_sql "
        SELECT id, model_name, description, created_at, last_used, updated_at
        FROM profiles 
        WHERE name = '$name';
    " true)
    
    local id model_name description created_at last_used updated_at
    IFS='|' read -r id model_name description created_at last_used updated_at <<< "$profile_data"
    
    local env_vars_data
    env_vars_data=$(execute_sql "
        SELECT key, value
        FROM profile_env_vars 
        WHERE profile_id = $id;
    " true)
    
    local env_vars_json='{}'
    if [[ -n "$env_vars_data" ]]; then
        while IFS='|' read -r key value; do
            if [[ -n "$key" ]]; then
                env_vars_json=$(echo "$env_vars_json" | jq --arg k "$key" --arg v "$value" '.[$k] = $v')
            fi
        done <<< "$env_vars_data"
    fi
    
    local profile_json
    profile_json=$(jq -n \
        --arg model_name "$model_name" \
        --arg description "$description" \
        --arg created "$created_at" \
        --arg last_used "${last_used:-}" \
        --argjson env_vars "$env_vars_json" \
        '{
            env_vars: $env_vars,
            model_name: $model_name,
            description: $description,
            created: $created,
            last_used: (if $last_used == "" then null else $last_used end)
        }'
    )
    
    echo "$profile_json"
}

# Get all profiles (returns JSON array for compatibility)
get_all_profiles() {
    local profiles_data
    profiles_data=$(execute_sql "
        SELECT name, model_name, description, created_at, last_used
        FROM profiles 
        ORDER BY name;
    " true)
    
    if [[ -z "$profiles_data" ]]; then
        echo '[]'
        return 0
    fi
    
    # Build JSON array using jq
    local json_array='[]'
    
    while IFS='|' read -r name model_name description created_at last_used; do
        if [[ -n "$name" ]]; then
            # Add profile object to array using jq
            json_array=$(echo "$json_array" | jq \
                --arg name "$name" \
                --arg model_name "$model_name" \
                --arg description "$description" \
                --arg created "$created_at" \
                --arg last_used "${last_used:-}" \
                '. += [{
                    name: $name,
                    model_name: $model_name,
                    description: $description,
                    created: $created,
                    last_used: (if $last_used == "" then null else $last_used end)
                }]'
            )
        fi
    done <<< "$profiles_data"
    
    echo "$json_array"
}

# Get profile names only
get_profile_names() {
    execute_sql "SELECT name FROM profiles ORDER BY name;" true
}

# Get profile count
get_profile_count() {
    execute_sql "SELECT COUNT(*) FROM profiles;" true
}

# Update profile
update_profile() {
    local name="$1"
    local model_name="$2"
    local description="$3"
    local env_vars_json="$4"
    
    if [[ -z "$name" ]]; then
        log_error "Profile name is required"
        return 1
    fi
    
    if ! profile_exists "$name"; then
        log_error "Profile '$name' does not exist"
        return 1
    fi
    
    # Escape single quotes
    name=$(printf '%s' "$name" | sed "s/'/''/g")
    
    # Update profile if model_name or description provided
    if [[ -n "$model_name" || -n "$description" ]]; then
        local update_sql="UPDATE profiles SET"
        local updates=()
        
        if [[ -n "$model_name" ]]; then
            model_name=$(printf '%s' "$model_name" | sed "s/'/''/g")
            updates+=("model_name = '$model_name'")
        fi
        
        if [[ -n "$description" ]]; then
            description=$(printf '%s' "$description" | sed "s/'/''/g")
            updates+=("description = '$description'")
        fi
        
        # Join updates with commas
        local IFS=','
        update_sql+=" ${updates[*]} WHERE name = '$name';"
        
        if ! execute_sql "$update_sql"; then
            log_error "Failed to update profile"
            return 1
        fi
    fi
    
    # Update environment variables if provided
    if [[ -n "$env_vars_json" ]]; then
        # Get profile ID
        local profile_id
        profile_id=$(execute_sql "SELECT id FROM profiles WHERE name = '$name';" true)
        
        # Clear existing environment variables
        execute_sql "DELETE FROM profile_env_vars WHERE profile_id = $profile_id;"
        
        # Insert new environment variables
        if [[ "$env_vars_json" != "{}" ]]; then
            while IFS=':' read -r key value; do
                if [[ -n "$key" && -n "$value" ]]; then
                    key=$(echo "$key" | xargs)
                    value=$(echo "$value" | xargs)
                    
                    if [[ -n "$key" && -n "$value" ]]; then
                        key=$(printf '%s' "$key" | sed "s/'/''/g")
                        value=$(printf '%s' "$value" | sed "s/'/''/g")
                        
                        local env_sql="
                            INSERT INTO profile_env_vars (profile_id, key, value)
                            VALUES ($profile_id, '$key', '$value');
                        "
                        
                        execute_sql "$env_sql"
                    fi
                fi
            done < <(echo "$env_vars_json" | sed 's/[{}"]//g' | tr ',' '\n' | grep ':')
        fi
    fi
    
    return 0
}

# Update profile last used timestamp
update_profile_last_used() {
    local name="$1"
    
    if [[ -z "$name" ]]; then
        log_error "Profile name is required"
        return 1
    fi
    
    name=$(printf '%s' "$name" | sed "s/'/''/g")
    
    local sql="
        UPDATE profiles 
        SET last_used = datetime('now')
        WHERE name = '$name';
    "
    
    execute_sql "$sql"
}

# Delete profile and all related data
delete_profile() {
    local name="$1"
    
    if [[ -z "$name" ]]; then
        log_error "Profile name is required"
        return 1
    fi
    
    if ! profile_exists "$name"; then
        log_error "Profile '$name' does not exist"
        return 1
    fi
    
    # Escape single quotes for SQL
    local escaped_name
    escaped_name=$(printf '%s' "$name" | sed "s/'/''/g")
    
    # Get profile ID for detailed cleanup
    local profile_id
    profile_id=$(execute_sql "SELECT id FROM profiles WHERE name = '$escaped_name';" true 2>/dev/null)
    
    if [[ -n "$profile_id" ]]; then
        # Count environment variables before deletion
        local env_var_count
        env_var_count=$(execute_sql "SELECT COUNT(*) FROM profile_env_vars WHERE profile_id = $profile_id;" true 2>/dev/null)
        
        # Delete profile and related data in a transaction
        local delete_sql="
            BEGIN TRANSACTION;
            
            -- Delete environment variables first (explicit cleanup)
            DELETE FROM profile_env_vars WHERE profile_id = $profile_id;
            
            -- Delete the profile itself
            DELETE FROM profiles WHERE id = $profile_id;
            
            COMMIT;
        "
        
        if ! execute_sql "$delete_sql" 2>/dev/null; then
            log_error "Failed to delete profile '$name'"
            return 1
        fi
        
        log_success "Profile ${PURPLE}'$name'${NC} deleted successfully"
    else
        log_error "Failed to get profile ID for '$name'"
        return 1
    fi
    
    return 0
}

clear_all_profiles() {
    local clear_sql="
        BEGIN TRANSACTION;
        DELETE FROM profiles;
        DELETE FROM auth_verification;
        COMMIT;
    "
    
    if ! execute_sql "$clear_sql"; then
        log_error "Failed to clear all profiles"
        log_info "Fall back to delete the whole database..."
        rm -rf "$DB_FILE" || {
            log_error "Operation failed!"
            log_info "You can manually delete it by running: ${PURPLE}rm -rf $DB_FILE${NC}"
            log_info "After that, please re-init LAM by running: ${PURPLE}lam init${NC}."
            return 1
        }
    fi
    
    return 0
}

# ----------------------------------- Metadata Operations -----------------------------------

# Set metadata key-value pair
set_metadata() {
    local key="$1"
    local value="$2"
    
    if [[ -z "$key" || -z "$value" ]]; then
        log_error "Metadata key and value are required"
        return 1
    fi
    
    key=$(printf '%s' "$key" | sed "s/'/''/g")
    value=$(printf '%s' "$value" | sed "s/'/''/g")
    
    local sql="
        INSERT OR REPLACE INTO metadata (key, value)
        VALUES ('$key', '$value');
    "
    
    execute_sql "$sql"
}

# Get metadata value
get_metadata() {
    local key="$1"
    
    if [[ -z "$key" ]]; then
        log_error "Metadata key is required"
        return 1
    fi
    
    key=$(printf '%s' "$key" | sed "s/'/''/g")
    
    execute_sql "SELECT value FROM metadata WHERE key = '$key';" true
}