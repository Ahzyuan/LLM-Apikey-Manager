#!/usr/bin/env bash

# LAM Utils Module
# Logging, validation, and utility functions

readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly PURPLE='\033[0;35m'
readonly GRAY='\033[0;90m'
readonly NC='\033[0m' # No Color

declare -a TEMP_FILES=()
declare -a TEMP_DIRS=()

# --------------------------------- Color Log ---------------------------------
# Log informational message with blue color
# Arguments:
#   $1 - message: The message to log
# Returns:
#   Always returns 0
# Globals:
#   BLUE, NC: Color codes for formatting
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

# Log success message with green color
# Arguments:
#   $1 - message: The success message to log
# Returns:
#   Always returns 0
# Globals:
#   GREEN, NC: Color codes for formatting
log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

# Log warning message with yellow color
# Arguments:
#   $1 - message: The warning message to log
# Returns:
#   Always returns 0
# Globals:
#   YELLOW, NC: Color codes for formatting
log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

# Log error message with red color
# Arguments:
#   $1 - message: The error message to log
# Returns:
#   Always returns 0
# Globals:
#   RED, NC: Color codes for formatting
log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Log message with gray color (for secondary information)
# Arguments:
#   $1 - message: The message to log in gray
# Returns:
#   Always returns 0
# Globals:
#   GRAY, NC: Color codes for formatting
log_gray() {
    echo -e "${GRAY}$1${NC}" >&2
}

# Log message with purple color (for highlights)
# Arguments:
#   $1 - message: The message to log in purple
# Returns:
#   Always returns 0
# Globals:
#   PURPLE, NC: Color codes for formatting
log_purple() {
    echo -e "${PURPLE}$1${NC}" >&2
}

# --------------------------------- Running Health ---------------------------------
# GC, garbage collection & cleanup
cleanup_temp_resources() {
    local file dir
    for file in "${TEMP_FILES[@]}"; do
        [[ -f "$file" ]] && rm -f "$file"
    done
    for dir in "${TEMP_DIRS[@]}"; do
        [[ -d "$dir" ]] && rm -rf "$dir"
    done
    TEMP_FILES=()
    TEMP_DIRS=()
}

# Check if all required system dependencies are installed
# Arguments:
#   None
# Returns:
#   0 if all dependencies are available, 1 if any are missing
# Globals:
#   None
check_dependencies() {
    local dependencies=("sqlite3" "openssl" "curl" "tar" "jq")
    local missing_deps=()
    local dep
    
    for dep in "${dependencies[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing_deps+=("$dep")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        log_info "Please install them using:"
        log_info "sudo apt-get update && sudo apt-get install -y ${missing_deps[*]}"
        exit 1
    fi
}

# Check if LAM has been properly initialized (database exists)
# Arguments:
#   None
# Returns:
#   0 if LAM is initialized, 1 if not initialized
# Globals:
#   DB_FILE: Path to the SQLite database file
check_initialization() {
    
    if [[ ! -f "$DB_FILE" ]]; then
        log_error "No LAM configuration found!"
        log_info "Please run ${PURPLE}'lam init'${NC} first to initialize LAM."
        return 1
    fi
    
    # Check if profiles table exists
    local table_count
    table_count=$(execute_sql "SELECT COUNT(*) FROM sqlite_master WHERE type='table' AND name='profiles';" true 2>/dev/null)
    
    if [[ "$table_count" -ne 1 ]]; then
        log_error "LAM configuration is corrupted!"
        log_info "You should need to run 'lam init' to reinitialize LAM."
        rm -rf "$DB_FILE" || {
            log_error "Failed to remove corrupted LAM configuration."
            log_info "Please manually delete the file ${PURPLE}'$DB_FILE'${NC} before reinitializing LAM."
        }
        return 1
    fi
}

# Check if profile argument is provided and valid
# Arguments:
#   $1 - profile_name: Name of the profile to validate
# Returns:
#   0 if profile name is valid, 1 if invalid or missing
# Globals:
#   None
check_profile_arg() { 
    local name="$1"
    local action="$2"
    
    local arg_error=false
    if [[ -z "$name" ]]; then
        log_error "Profile name is required!"
        log_info "Usage: ${PURPLE}lam $action <profile_name>${NC}"
        arg_error=true
    elif ! profile_exists "$name"; then
        log_error "Profile ${PURPLE}'$name'${NC} not found!"
        arg_error=true
    fi
    
    if $arg_error; then
        local profiles_cnt
        profiles_cnt=$(get_profile_count)
        if [[ $profiles_cnt -gt 0 ]]; then
            log_info "Available profiles:" >&2
            get_profile_names | sed 's/^/• /' >&2
        else
            log_info "No profiles found" >&2
            log_gray "You can use ${PURPLE}'lam add <profile_name>'${GRAY} to add a profile" >&2
        fi
        exit 1
    fi
}

# -------------------------------- Input Validation --------------------------------

# Validate input length against security limits
# Arguments:
#   $1 - input: The input string to validate
#   $2 - max_length: Maximum allowed length (optional, uses MAX_INPUT_LENGTH if not provided)
# Returns:
#   0 if input length is valid, 1 if too long
# Globals:
#   MAX_INPUT_LENGTH: Global maximum input length constant
validate_input_length() {
    local input="$1"
    local max_length="${2:-$MAX_INPUT_LENGTH}"
    
    if [[ ${#input} -gt $max_length ]]; then
        log_error "Input exceeds maximum length of $max_length characters"
        return 1
    fi
    return 0
}

# Sanitize input to prevent injection attacks
# Arguments:
#   $1 - input: The input string to sanitize
# Returns:
#   0 on success, outputs sanitized string to stdout
# Globals:
#   None
sanitize_input() {
    local input="$1"
    # Remove null bytes, carriage returns, and newlines
    # Also trim leading and trailing whitespace
    printf '%s' "$input" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//' | tr -d '\0\r\n'
}

# Validate environment variable key format
# Arguments:
#   $1 - key: The environment variable key to validate
# Returns:
#   0 if key format is valid, 1 if invalid
# Globals:
#   None
validate_env_key() {
    local key="$1"
    
    # Must start with letter or underscore, contain only alphanumeric and underscore
    if [[ ! "$key" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
        log_error "Invalid environment variable key format: $key"
        log_info "Environment variable keys must start with a letter or underscore, and contain only alphanumeric and underscore characters."
        return 1
    fi
    
    # Check length limits
    if [[ ${#key} -lt 1 || ${#key} -gt 64 ]]; then
        log_error "Environment variable key must be 1-64 characters: $key"
        return 1
    fi
    
    return 0
}

# Validate environment variable value
# Arguments:
#   $1 - value: The environment variable value to validate
# Returns:
#   0 if value is valid, 1 if invalid or too long
# Globals:
#   MAX_INPUT_LENGTH: Maximum allowed value length
validate_env_value() {
    local value="$1"
    
    # Check for dangerous characters
    local danger_chars_list
    mapfile -t danger_chars_list < <(grep -o '[\$`!&;|<>]' <<<"$value" | sort -u)
    
    if [[ ${#danger_chars_list[@]} -gt 0 ]]; then
        local IFS=","
        log_error "Environment variable value contains following potentially dangerous characters:"
        log_error "Dangerous characters (separated by commas): ${danger_chars_list[*]}"
        return 1
    fi
    
    # Check length limits
    if [[ ${#value} -gt 2048 ]]; then
        log_error "Environment variable value exceeds maximum length of 2048 characters"
        return 1
    fi
    
    return 0
}

# -------------------------------------- Misc -------------------------------------

# Create a secure temporary file with proper permissions
# Arguments:
#   None
# Returns:
#   0 on success, outputs temp file path to stdout; 1 on failure
# Globals:
#   TEMP_FILES: Array to track temporary files for cleanup
create_temp_file() {
    local temp_file
    temp_file=$(mktemp) || {
        log_error "Failed to create temporary file"
        return 1
    }
    
    # Set secure permissions
    chmod 600 "$temp_file" || {
        rm -f "$temp_file"
        log_error "Failed to set secure permissions on temporary file"
        return 1
    }
    
    # Add to cleanup list
    TEMP_FILES+=("$temp_file")
    
    echo "$temp_file"
}

# Interactively collect environment variable from user
# Arguments:
#   $1 - key: The environment variable key
#   $2 - current_value: Current value (optional, for editing)
# Returns:
#   0 on success, outputs JSON object to stdout; 1 on failure
# Globals:
#   None
collect_env_var() {
    local field_name="$1"
    local prompt="$2"
    local master_password="$3"
    local env_vars_json="$4"
    local required="${5:-false}"  # required or optional
    local mask_display="${6:-true}"  # mask_value or show_value
    local env_type="${7:-other}"  # environment variable type: api_key, base_url, other

    if [[ -z "$master_password" ]]; then
        log_error "Master password is required to collect environment variables!"
        return 1
    fi
     
    if [[ -z "$env_vars_json" ]];then
        log_error "Environment variables collector in json string is required!"
        return 1
    fi
    
    while true; do
        echo -en "${PURPLE}$prompt${NC}: " >&2
        local input
        if ! read -r input; then
            log_error "Failed to read input"
            return 1
        fi
        
        # Handle optional fields
        if [[ $required == false && -z "$input" ]]; then
            log_info "Skipped: $field_name"
            echo ""
            return 0 
        elif [[ $required && -z "$input" ]]; then
            log_error "$field_name is required!"
            continue
        fi
        
        # Validate and parse input
        input=$(sanitize_input "$input")
        if [[ ! "$input" =~ ^[A-Za-z_][A-Za-z0-9_]*=.+$ ]]; then
            log_error "Invalid input, Use KEY=VALUE format!"
            continue
        fi
        
        local key="${input%%=*}"
        local value="${input#*=}"
        
        if validate_env_key "$key" && validate_env_value "$value"; then
            local encrypted_value
            if ! encrypted_value=$(encrypt_data "$value" "$master_password"); then
                log_error "Failed to encrypt value for ${PURPLE}$key${NC}"
                return 1
            fi
            
            # dump to env_vars_json with type information
            echo "$env_vars_json" | jq \
                --arg key "$key" \
                --arg value "$encrypted_value" \
                --arg type "$env_type" \
                '.[$key] = {value: $value, type: $type}'

            if $mask_display;then
                log_success "Added: $key = ******"
            else
                log_success "Added: $key = $value"
            fi

            return 0
        fi
    done
}