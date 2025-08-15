#!/usr/bin/env bash

# LAM (LLM API Manager) Installation Script
# This script installs the LAM system with all library dependencies

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
NC='\033[0m'

# Log informational message during installation
# Arguments:
#   $1 - message: Message to log
# Returns:
#   Always returns 0
# Globals:
#   BLUE, NC: Color codes for formatting
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

# Log success message during installation
# Arguments:
#   $1 - message: Success message to log
# Returns:
#   Always returns 0
# Globals:
#   GREEN, NC: Color codes for formatting
log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

# Log warning message during installation
# Arguments:
#   $1 - message: Warning message to log
# Returns:
#   Always returns 0
# Globals:
#   YELLOW, NC: Color codes for formatting
log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Log error message during installation
# Arguments:
#   $1 - message: Error message to log
# Returns:
#   Always returns 0
# Globals:
#   RED, NC: Color codes for formatting
log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Log highlighted message during installation
# Arguments:
#   $1 - message: Message to log in purple
# Returns:
#   Always returns 0
# Globals:
#   PURPLE, NC: Color codes for formatting
log_purple() {
    echo -e "${PURPLE}$1${NC}" >&2
}

# Check for required system dependencies and versions
# Arguments:
#   None
# Returns:
#   0 if all dependencies are satisfied, 1 if missing dependencies
# Globals:
#   None
check_dependencies() {
    local deps=("sqlite3" "openssl" "curl" "tar" "jq")
    local missing_deps=()

    log_info "Checking dependencies..."
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        log_info "Please install them with: sudo apt-get install -y ${missing_deps[*]}"
        exit 1
    fi
    
    # Check OpenSSL version (minimum 1.1.1 for good PBKDF2 support)
    local openssl_version
    openssl_version=$(openssl version | cut -d' ' -f2 | sed 's/[a-z].*$//')
    local min_version="1.1.1"
    if [[ "$(printf '%s\n' "$min_version" "$openssl_version" | sort -V | head -n1)" != "$min_version" ]]; then
        log_warning "OpenSSL version $openssl_version may have limited security features"
        log_warning "Consider upgrading to OpenSSL 1.1.1 or later using: sudo apt-get install openssl"
    fi
    
    # Check SQLite version (minimum 3.7.0 for good features)
    local sqlite_version
    sqlite_version=$(sqlite3 --version 2>/dev/null | cut -d' ' -f1)
    local min_sqlite_version="3.7.0"
    if [[ -n "$sqlite_version" && "$(printf '%s\n' "$min_sqlite_version" "$sqlite_version" | sort -V | head -n1)" != "$min_sqlite_version" ]]; then
        log_warning "SQLite version $sqlite_version may have limited features"
        log_warning "Consider upgrading to SQLite 3.7.0 or later using: sudo apt-get install sqlite3"
    fi

    log_success "All dependencies are installed"
}

# Determine installation scope and set directory variables
# Arguments:
#   None
# Returns:
#   Always returns 0
# Globals:
#   INSTALL_DIR, LAM_LIB_DIR: Set based on user privileges
check_install_scope() {
    if [[ $EUID -eq 0 ]]; then
        # Running as root - system-wide installation
        INSTALL_DIR="/usr/local/bin"
        LAM_LIB_DIR="/usr/local/share/lam"
        log_info "Installing system-wide to ${PURPLE}$INSTALL_DIR${NC}"
        log_info "LAM libraries will be installed to ${PURPLE}$LAM_LIB_DIR${NC}"
    else
        # Running as regular user - user installation
        INSTALL_DIR="$HOME/.local/bin"
        LAM_LIB_DIR="$HOME/.local/share/lam"
        log_info "Installing for current user to ${PURPLE}$INSTALL_DIR${NC}"
        log_info "LAM libraries will be installed to ${PURPLE}$LAM_LIB_DIR${NC}"
        
        # Create user bin directory if it doesn't exist
        mkdir -p "$INSTALL_DIR"
        
        # Check if INSTALL_DIR is in PATH
        if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
            log_warning "Add ${PURPLE}$INSTALL_DIR${NC} to your PATH by adding this line to your ~/.bashrc or ~/.zshrc:"
            log_purple "export PATH=\"\$PATH:$INSTALL_DIR\""
        fi
    fi
}

# Validate that all required LAM files are present for installation
# Arguments:
#   None
# Returns:
#   0 if all files are present, 1 if missing files
# Globals:
#   None
check_file_integrity() {
    log_info "Checking for required files for LAM installation..."
    required_modules=("security.sh" "config.sh" "utils.sh")
    required_command_modules=("core.sh" "backup.sh" "help.sh" "system.sh")
    local missing_modules=()
    local missing_command_modules=()

    # Check for modular executable
    if [[ ! -f "lam" ]]; then
        log_error "lam script not found in current directory!"
        log_info "Make sure you're running this installation script from the LAM project directory"
        exit 1
    fi
    
    # Check for lib directory
    if [[ ! -d "lib" ]]; then
        log_error "lib directory not found in current directory!"
        log_info "Please re-clone the LAM repository and try again"
        exit 1
    else
        # Validate all required library modules exist
        for module in "${required_modules[@]}"; do
            if [[ ! -f "lib/$module" ]]; then
                missing_modules+=("$module")
            fi
        done
        
        if [[ ${#missing_modules[@]} -gt 0 ]]; then
            log_error "Missing required library modules: ${RED}${missing_modules[*]}${NC}"
            log_info "Please re-clone the LAM repository and try again"
            exit 1
        fi
    fi
    
    # Check for lib/commands directory
    if [[ ! -d "lib/commands" ]]; then
        log_error "lib/commands directory not found in current directory!"
        log_info "Please re-clone the LAM repository and try again"
        exit 1
    else
        # Validate all required command modules exist
        for module in "${required_command_modules[@]}"; do
            if [[ ! -f "lib/commands/$module" ]]; then
                missing_command_modules+=("$module")
            fi
        done
        
        if [[ ${#missing_command_modules[@]} -gt 0 ]]; then
            log_error "Missing required command modules: ${RED}${missing_command_modules[*]}${NC}"
            log_info "Please re-clone the LAM repository and try again"
            log_info "LAM Repo: ${PURPLE}https://github.com/Ahzyuan/LLM-Apikey-Manager${NC}"
            exit 1
        fi
    fi
    
    # Check for VERSION file
    if [[ ! -f "VERSION" ]]; then
        log_warning "VERSION file not found - version will show as 'unknown'"
        echo "unknown" > "VERSION"
    fi
    
    log_success "All required files found for installation"
}

# Install LAM executable and library files to system
# Arguments:
#   None
# Returns:
#   0 on successful installation, 1 on failure
# Globals:
#   INSTALL_DIR, LAM_LIB_DIR: Installation directories
install_lam() {
    log_info "Installing LAM (LLM API Manager)..."
    
    
    # Remove old installation if it exists
    local lam_install_dir="$LAM_LIB_DIR"
    local wrapper_script="$INSTALL_DIR/lam" # wrapper script in bin dir
    if [[ -d "$lam_install_dir" ]]; then
        log_warning "Removing existing LAM installation..."
        rm -rf "$lam_install_dir"
    fi
    if [[ -e "$wrapper_script" ]] || [[ -L "$wrapper_script" ]]; then
        rm -rf "$wrapper_script"
    fi
    
    # Create directory structure
    mkdir -p "$lam_install_dir/lib/commands"
    log_info "Creating LAM library directory: ${PURPLE}$lam_install_dir${NC}"
    
    # Install main executable
    cp "lam" "$lam_install_dir/lam"
    chmod +x "$lam_install_dir/lam"
    
    # Install VERSION file
    cp "VERSION" "$lam_install_dir/"
    chmod 644 "$lam_install_dir/VERSION"
    
    # Install library modules
    for module in "${required_modules[@]}"; do
        cp "lib/$module" "$lam_install_dir/lib/"
        chmod 644 "$lam_install_dir/lib/$module"
    done
    
    # Install command modules
    for module in "${required_command_modules[@]}"; do
        cp "lib/commands/$module" "$lam_install_dir/lib/commands/"
        chmod 644 "$lam_install_dir/lib/commands/$module"
    done
            
    # Create a wrapper script that calls the main executable
    cat > "$wrapper_script" << EOF
#!/usr/bin/env bash
# LAM wrapper script - calls the main modular executable
exec "$lam_install_dir/lam" "\$@"
EOF
    chmod +x "$wrapper_script"
    
    log_success "LAM executable installed to ${PURPLE}$INSTALL_DIR/lam${NC}"
    log_success "LAM libraries installed to ${PURPLE}$lam_install_dir${NC}"
}

# Test LAM installation by running basic commands
# Arguments:
#   None
# Returns:
#   0 if installation tests pass, 1 if tests fail
# Globals:
#   INSTALL_DIR: Installation directory for testing
test_installation() {
    log_info "Testing LAM installation..."
    
    # Dynamically find the lam command
    local lam_command
    if ! lam_command=$(command -v lam 2>/dev/null); then
        log_error "LAM command not found in PATH"
        log_info "Trying to find LAM in installation directory: ${PURPLE}$INSTALL_DIR${NC}"
        
        # Fallback: check installation directory directly
        if [[ -x "$INSTALL_DIR/lam" ]]; then
            lam_command="$INSTALL_DIR/lam"
            log_warning "LAM found at ${PURPLE}$lam_command${NC} but not in PATH"
            log_warning "You may need to add ${PURPLE}$INSTALL_DIR${NC} to your PATH or restart your shell"
        else
            log_error "LAM executable not found anywhere"
            log_info "Please re-clone the LAM repository and try again"
            log_info "LAM Repo: ${PURPLE}https://github.com/Ahzyuan/LLM-Apikey-Manager${NC}"
            return 1
        fi
    else
        log_success "LAM command found at: ${PURPLE}$lam_command${NC}"
    fi
    echo
        
    # Test help command
    log_info "Testing help command..."
    local help_output
    if ! help_output=$("$lam_command" -h 2>&1); then
        log_error "Failed to execute 'lam -h'"
        log_error "Output: $help_output"
        return 1
    fi
        
    log_success "All installation tests passed!"
    log_success "LAM is properly installed and accessible 🚀!"
    return 0
}

# Main installation function that orchestrates the entire process
# Arguments:
#   $@ - All command line arguments passed to installer
# Returns:
#   0 on successful installation, 1 on failure
# Globals:
#   Uses all installation functions and variables
main() {
    local version=$(cat "VERSION" 2>/dev/null || echo "unknown")
    echo "LAM (LLM API Manager) Installation"
    echo "================================="
    echo "Version: $version"
    echo
    
    check_install_scope
    echo 

    check_dependencies
    echo 

    check_file_integrity
    echo

    install_lam
    hash -r 
    echo

    if test_installation; then
        echo
        log_info "💡 To get started:"
        log_info "1. Run ${PURPLE}'lam init'${NC} to initialize the tool"
        log_info "2. Run ${PURPLE}'lam add <profile-name>'${NC} to add your first API profile"
        log_info "3. Run ${PURPLE}'lam help'${NC} for more information"
        echo 
        log_info "For detailed examples and usage, refer to: ${PURPLE}https://github.com/Ahzyuan/LLM-Apikey-Manager${NC} 🚀."
        log_info "Looking forward to your star ⭐, feedback 💬 and contributions 🤝!"
        echo
    else
        echo
        log_error "Installation completed but tests failed!"
        log_error "LAM may not work correctly. Please check the errors above."
        echo
        exit 1
    fi
    
}

main "$@"