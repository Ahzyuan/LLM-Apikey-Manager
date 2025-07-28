#!/bin/bash

# LAM Utils Module
# Logging, validation, and utility functions

# Colors for output
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly GRAY='\033[0;37m'
readonly NC='\033[0m' # No Color

# Global variables for cleanup
declare -a TEMP_FILES=()
declare -a TEMP_DIRS=()

# Cleanup function
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

# Utility functions
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

# Enhanced error handling
handle_error() {
    local exit_code=$1
    local message="$2"
    local line_number=${3:-"unknown"}
    
    log_error "$message (line: $line_number)"
    cleanup_temp_resources
    exit "$exit_code"
}

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
    if [[ "$value" =~ [\$\`\!\&\;\|\<\>] ]]; then
        log_error "Environment variable value contains potentially dangerous characters"
        return 1
    fi
    
    # Check length limits
    if [[ ${#value} -gt 2048 ]]; then
        log_error "Environment variable value exceeds maximum length of 2048 characters"
        return 1
    fi
    
    return 0
}

# Check dependencies
check_dependencies() {
    local missing_deps=()
    
    if ! command -v jq >/dev/null 2>&1; then
        missing_deps+=("jq")
    fi
    
    if ! command -v openssl >/dev/null 2>&1; then
        missing_deps+=("openssl")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        echo
        log_info "Please install them using:"
        echo "sudo apt-get update && sudo apt-get install ${missing_deps[*]}"
        exit 1
    fi
}

# Check if LAM is initialized
check_initialization() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        log_error "LAM is not initialized!"
        echo
        log_info "Please run 'lam init' first to set up your master password."
        exit 1
    fi
}

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

# Get version from VERSION file
get_version() {
    local version_file
    local script_dir
    
    # Get script directory from the main lam script location
    if [[ -n "${BASH_SOURCE[0]}" ]]; then
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    else
        # Fallback: try common locations
        for dir in "$(pwd)" "$(dirname "$(which lam 2>/dev/null)")" "/usr/local/bin" "$HOME/.local/bin"; do
            if [[ -f "$dir/VERSION" ]]; then
                script_dir="$dir"
                break
            fi
        done
    fi
    
    version_file="$script_dir/VERSION"
    
    if [[ -f "$version_file" ]]; then
        head -n1 "$version_file" | tr -d '[:space:]'
    else
        echo "3.1.0"  # Fallback version
    fi
}

# Get version description from VERSION file
get_version_description() {
    local version_file
    local script_dir
    
    # Get script directory from the main lam script location
    if [[ -n "${BASH_SOURCE[0]}" ]]; then
        script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    else
        # Fallback: try common locations
        for dir in "$(pwd)" "$(dirname "$(which lam 2>/dev/null)")" "/usr/local/bin" "$HOME/.local/bin"; do
            if [[ -f "$dir/VERSION" ]]; then
                script_dir="$dir"
                break
            fi
        done
    fi
    
    version_file="$script_dir/VERSION"
    
    if [[ -f "$version_file" ]]; then
        tail -n +2 "$version_file" | grep -v '^[[:space:]]*$' | head -n1
    else
        echo "Security Hardened - Enhanced with security improvements and better error handling"
    fi
}

