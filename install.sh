#!/usr/bin/env bash

# LAM (LLM API Manager) Installation Script
# This script installs the modular LAM system with all library dependencies

set -euo pipefail

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}


# Check dependencies
check_dependencies() {
    local deps=("jq" "openssl" "curl" "tar")
    local missing_deps=()

    log_info "Checking dependencies..."
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing_deps+=("$dep")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing dependencies: ${missing_deps[*]}"
        log_info "Please install them with: sudo apt-get install ${missing_deps[*]}"
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
    
    # Check jq version (minimum 1.5 for good JSON support)
    local jq_version
    jq_version=$(jq --version 2>/dev/null | grep -o '[0-9.]*' | head -1)
    local min_jq_version="1.5"
    if [[ -n "$jq_version" && "$(printf '%s\n' "$min_jq_version" "$jq_version" | sort -V | head -n1)" != "$min_jq_version" ]]; then
        log_warning "jq version $jq_version may have limited features"
        log_warning "Consider upgrading to jq 1.5 or later using: sudo apt-get install jq"
    fi

    log_success "All dependencies are installed"
}

# Determine installation scope and directories
check_install_scope() {
    if [[ $EUID -eq 0 ]]; then
        # Running as root - system-wide installation
        INSTALL_DIR="/usr/local/bin"
        LAM_LIB_DIR="/usr/local/share/lam"
        log_info "Installing system-wide to $INSTALL_DIR"
        log_info "LAM libraries will be installed to $LAM_LIB_DIR"
    else
        # Running as regular user - user installation
        INSTALL_DIR="$HOME/.local/bin"
        LAM_LIB_DIR="$HOME/.local/share/lam"
        log_info "Installing for current user to $INSTALL_DIR"
        log_info "LAM libraries will be installed to $LAM_LIB_DIR"
        
        # Create user bin directory if it doesn't exist
        mkdir -p "$INSTALL_DIR"
        
        # Check if INSTALL_DIR is in PATH
        if [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
            log_warning "Add $INSTALL_DIR to your PATH by adding this line to your ~/.bashrc or ~/.zshrc:"
            echo "export PATH=\"\$PATH:$INSTALL_DIR\""
        fi
    fi
}

# Validate modular LAM installation files
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
            log_error "Missing required library modules: ${missing_modules[*]}"
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
            log_error "Missing required command modules: ${missing_command_modules[*]}"
            log_info "Please re-clone the LAM repository and try again"
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

# Install the modular LAM system
install_lam() {
    log_info "Installing LAM (LLM API Manager)..."
    
    # Create LAM library directory structure (separate from bin)
    local lam_install_dir="$LAM_LIB_DIR"
    
    # Remove old installation if it exists
    if [[ -d "$lam_install_dir" ]]; then
        rm -rf "$lam_install_dir"
    fi
    
    # Create directory structure
    mkdir -p "$lam_install_dir/lib/commands"
    log_info "Creating LAM library directory: $lam_install_dir"
    
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
    
    # Create wrapper script in bin directory
    local wrapper_script="$INSTALL_DIR/lam"
    
    # Remove any existing lam file/link/directory
    if [[ -e "$wrapper_script" ]] || [[ -L "$wrapper_script" ]]; then
        rm -rf "$wrapper_script"
    fi
    
    # Create a wrapper script that calls the main executable
    cat > "$wrapper_script" << EOF
#!/usr/bin/env bash
# LAM wrapper script - calls the main modular executable
exec "$lam_install_dir/lam" "\$@"
EOF
    chmod +x "$wrapper_script"
    
    log_success "LAM executable installed to $INSTALL_DIR/lam"
    log_success "LAM libraries installed to $lam_install_dir"
}

# Test LAM installation
test_installation() {
    log_info "Testing LAM installation..."
    
    # Dynamically find the lam command
    local lam_command
    if ! lam_command=$(command -v lam 2>/dev/null); then
        log_error "LAM command not found in PATH"
        log_info "Trying to find LAM in installation directory: $INSTALL_DIR"
        
        # Fallback: check installation directory directly
        if [[ -x "$INSTALL_DIR/lam" ]]; then
            lam_command="$INSTALL_DIR/lam"
            log_warning "LAM found at $lam_command but not in PATH"
            log_info "You may need to add $INSTALL_DIR to your PATH or restart your shell"
        else
            log_error "LAM executable not found anywhere"
            log_info "Please re-clone the LAM repository and try again"
            return 1
        fi
    else
        log_success "LAM command found at: $lam_command"
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
    log_success "LAM is properly installed and accessible🚀!"
    return 0
}

# Main installation function
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
        log_info "To get started:"
        log_info "1. Run 'lam init' to initialize the tool"
        log_info "2. Run 'lam add <name>' to add your first API configuration"
        log_info "3. Run 'lam help' for more information"
        echo
    else
        echo
        log_error "Installation completed but tests failed!"
        log_error "LAM may not work correctly. Please check the errors above."
        exit 1
    fi
    
}

main "$@"