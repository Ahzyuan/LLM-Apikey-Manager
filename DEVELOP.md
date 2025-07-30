# LAM (LLM API Manager) - Development Document

## ① Project Structure

```
lam/
├── lam                    # Main executable script
├── install.sh             # Installation script
├── lib/                   # Library modules
│   ├── commands.sh       # Command implementations
│   ├── config.sh         # Configuration management
│   ├── security.sh       # Security and encryption
│   └── utils.sh          # Utilities and logging
├── VERSION                # Version information
├── README.md              # Documentation
└── PROJECT_SUMMARY.md     # Project summary
```

## ② Main Entry Point

**Location:** `./lam`  
**Purpose:** Main executable that orchestrates all functionality

### 1. Key Functions:

- `main()`: Main entry point with command routing
  - Handles command-line argument parsing
  - Routes to appropriate command functions
  - Implements error handling and initialization checks

### 2. Global Variables:
- `SCRIPT_DIR`: Script installation directory
- `CONFIG_DIR`: User configuration directory (~/.config/lam)
- `CONFIG_FILE`: Encrypted configuration file path
- `LOCK_FILE`: Process lock file path
- `SESSION_FILE`: Session management file path
- Security constants: `MAX_PASSWORD_LENGTH`, `MIN_PASSWORD_LENGTH`, etc.

## ③ Installation Script

**Lines:** `install.sh`
**Purpose:** System installation and setup  

#### Key Functions:

- `log_info()`, `log_success()`, `log_warning()`, `log_error()`: Installation logging
- `check_dependencies()`: Verify system dependencies
- `install_lam()`: Install LAM to system directories
- `setup_completion()`: Set up bash completion
- `main()`: Main installation orchestrator

## ④ Library Modules

### 1. Commands Module

**Location:** `lib/commands.sh`  
**Purpose:** Implementation of all user-facing commands  

#### Core Command Functions:

- `cmd_init()`: Initialize or reset the master password
- `cmd_add()`: Add new API profile
- `cmd_list()`: List all profiles with formatting
- `cmd_show()`: Show specific profile details
- `cmd_use()`: Export profile to environment variables
- `cmd_edit()`: Edit existing profile configuration
- `cmd_delete()`: Delete profile with confirmation
- `cmd_test()`: Test API connection
- `cmd_backup()`: Backup profiles to file
- `cmd_stats()`: Show `lam`'s statistics and status

#### Utility Command Functions:

- `cmd_update()`: Update LAM to newest version
- `cmd_uninstall()`: Uninstall LAM completely
- `cmd_help()`: Display help information
- `cmd_version()`: Show version information

### 2. Configuration Module

**Location:** `lib/config.sh`   
**Purpose:** Configuration file management and validation  

#### Core Functions:

- `init_config_dir()`: Initialize configuration directory
- `validate_config()`: Validate JSON configuration structure
- `get_session_config()`: Get config from session or decrypt
- `save_session_config()`: Save config with validation
- `load_config()`: Legacy config loading function
- `save_config()`: Legacy config saving function

### 3. Security Module

**Lines:** `lib/security.sh`   
**Purpose:** Password handling, encryption, and security functions  

#### Password Management:

- `get_master_password()`: Secure password input with validation
- `get_verified_master_password()`: Get and verify master password

#### Encryption Functions:
- `encrypt_data()`: AES-256-CBC encryption with PBKDF2
- `decrypt_data()`: AES-256-CBC decryption

#### Session Management:
- `is_session_valid()`: Check if session is still valid
- `create_session()`: Create new session with timeout

### 4. Utils Module

**Lines:** `lib/utils.sh`   
**Purpose:** Logging, validation, and utility functions  

#### Logging Functions:

- `log_info()`: Info level logging
- `log_success()`: Success level logging
- `log_warning()`: Warning level logging
- `log_error()`: Error level logging
- `log_gray()`: Gray text logging

#### Error Handling:

- `handle_error()`: Enhanced error handling with cleanup
- `cleanup_temp_resources()`: Clean up temporary files

#### Validation Functions:

- `validate_input_length()`: Validate input length limits
- `sanitize_input()`: Sanitize input to prevent injection
- `validate_env_key()`: Validate environment variable names
- `validate_env_value()`: Validate environment variable values

#### System Functions:

- `check_dependencies()`: Check for required dependencies
- `check_initialization()`: Verify LAM is initialized
- `create_temp_file()`: Create secure temporary files
- `get_version_info()`: Get version information


## ⑤ Configuration Structure

```json
{
  "profiles": {
    "profile_name": {
      "api_key": "encrypted_key",
      "base_url": "api_endpoint",
      "provider": "provider_name"
    }
  },
  "metadata": {
    "created": "ISO_timestamp",
    "version": "version_number"
  }
}
```

## ⑥ Command Flow

1. **Main Entry** (`lam` script) → Parse arguments
2. **Dependency Check** (`utils.sh`) → Verify jq, openssl
3. **Initialization Check** (`config.sh`) → Verify setup
4. **Authentication** (`security.sh`) → Session or password
5. **Command Execution** (`commands.sh`) → Specific functionality
6. **Configuration Update** (`config.sh`) → Save changes
7. **Cleanup** (`utils.sh`) → Remove temporary files

## ⑦ Development Guidelines

### Adding New Commands:

1. Add command function to `lib/commands.sh`
2. Add command routing in `lam` main function
3. Update help text in `cmd_help()`
4. Follow existing error handling patterns

### Security Considerations:
- Always validate input lengths and formats
- Use secure temporary file creation
- Implement proper cleanup on exit
- Follow principle of least privilege
