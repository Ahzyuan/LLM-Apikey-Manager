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
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_gray() {
    echo -e "${GRAY}$1${NC}" >&2
}

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

check_dependencies() {
    local dependencies=("sqlite3" "openssl" "curl" "tar")
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

# Check if LAM is initialized
check_initialization() {
    if [[ ! -f "$DB_FILE" ]]; then
        log_error "LAM is not initialized!"
        log_info "Please run 'lam init' first to set up your master password."
        return 1
    fi
}

# -------------------------------- Input Validation --------------------------------
# Secure input validation functions
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
sanitize_input() {
    local input="$1"
    # Remove null bytes, carriage returns, and newlines
    printf '%s' "$input" | tr -d '\0\r\n'
}

# Validate environment variable key format
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
validate_env_value() {
    local value="$1"
    
    # Check for dangerous characters
    local danger_chars_list=($(grep -o '[\$\`\!\&\;\|\<\>]' <<<"$value" | sort -u))
    
    local char
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
# Create secure temporary file
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

