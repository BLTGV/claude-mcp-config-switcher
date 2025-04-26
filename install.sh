#!/bin/sh

# Installer for claude-mcp-manager (POSIX sh compatible)

set -e # Exit immediately if a command exits with a non-zero status.

SCRIPT_VERSION="0.1.0" # Match this with the main script's version

# Define cleanup function
cleanup() {
  # Add log_debug if available, otherwise use print_info
  if command -v log_debug >/dev/null 2>&1; then
      log_debug "Running cleanup..."
  else
      print_info "Running cleanup..."
  fi
  if [ -n "$TEMP_DOWNLOAD_DIR" ] && [ -d "$TEMP_DOWNLOAD_DIR" ]; then
    if command -v log_debug >/dev/null 2>&1; then
        log_debug "Cleaning up temporary download directory: $TEMP_DOWNLOAD_DIR"
    else
        print_info "Cleaning up temporary download directory: $TEMP_DOWNLOAD_DIR"
    fi
    rm -rf "$TEMP_DOWNLOAD_DIR"
  fi
}

# Set trap to call cleanup function on EXIT, INT, TERM, HUP
trap cleanup EXIT INT TERM HUP

# --- Configuration ---
APP_NAME="claude-mcp-manager"
DEFAULT_LIB_DIR="/usr/local/lib/$APP_NAME"
USER_LIB_DIR="$HOME/.local/lib/$APP_NAME"
DEFAULT_BIN_DIR="/usr/local/bin"
USER_BIN_DIR="$HOME/.local/bin"

# Determine script's own directory to find sources relative to it
# This makes it work better with `curl | sh` where CWD might not be the project root
INSTALLER_DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd -P)

SOURCE_MAIN_SCRIPT="$INSTALLER_DIR/src/$APP_NAME"
SOURCE_UTILS_SCRIPT="$INSTALLER_DIR/src/utils.sh"

# --- Colors (copied from utils.sh for standalone use) ---
# Use printf for better compatibility than echo -e
COLOR_RESET='\033[0m'
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_BOLD='\033[1m'

print_color() {
    color="$1"
    shift
    printf "%b%s%b\n" "$color" "$*" "$COLOR_RESET"
}
print_bold() { print_color "$COLOR_BOLD" "$@"; }
print_error() { print_color "$COLOR_RED" "ERROR: $@" >&2; }
print_warning() { print_color "$COLOR_YELLOW" "WARNING: $@"; }
print_success() { print_color "$COLOR_GREEN" "SUCCESS: $@"; }
# Define log_debug function only if it's not already defined (might be sourced later)
if ! command -v log_debug >/dev/null 2>&1; then
    log_debug() { printf "DEBUG: %s\n" "$@" >&2; }
fi
# Use log_debug or print_info based on availability for consistency
print_info() { 
    if command -v log_debug >/dev/null 2>&1; then
        log_debug "INFO: $@"
    else
        printf "INFO: %s\n" "$@"
    fi
}

# --- Helper Functions ---
echo_bold() {
    print_bold "$1"
}

check_command() {
    command -v "$1" >/dev/null 2>&1
}

path_contains() {
    # POSIX-compliant way to check if a directory is in PATH
    echo ":$PATH:" | grep -q ":$1:"
}

# --- Dependency Checks ---
check_dependencies() {
    print_info "Checking dependencies..."
    missing_deps=0
    # Need curl for downloading if in curl|sh mode
    if ! check_command curl; then
        print_error "Dependency 'curl' not found. Cannot download source files if needed."
        missing_deps=1
    fi
    if ! check_command jq; then
        print_error "Dependency 'jq' not found. Please install it (e.g., 'brew install jq' or 'sudo apt-get install jq')."
        missing_deps=1
    fi
    if ! check_command pgrep; then
        print_error "Dependency 'pgrep' not found. It should be part of standard system utilities."
        missing_deps=1
    fi
    # Check if bash is available, as the main script requires it
    if ! check_command bash; then
        print_error "Dependency 'bash' not found. The main script requires bash to run."
        missing_deps=1
    fi
    # Simple check for bash regex support (might not be perfect but better than nothing)
    if ! bash -c '[[ "test" =~ ^test$ ]]' > /dev/null 2>&1; then
        print_warning "Installed 'bash' might not support regex needed by the script. Proceed with caution."
        # Not making this fatal, as the check might be unreliable
    fi
    if ! check_command mktemp; then
        print_error "Dependency 'mktemp' not found. It should be part of standard system utilities."
        missing_deps=1
    fi

    if [ "$missing_deps" -ne 0 ]; then
        print_error "Please install missing dependencies and try again."
        exit 1
    fi
    print_success "All dependencies found."
}

# --- Installation Logic ---

# 1. Check Source Files and Download if Necessary
print_info "Checking source files..."
TEMP_DOWNLOAD_DIR="" # Initialize temporary directory variable

# Check if source files exist relative to the installer's calculated directory
if [ ! -f "$SOURCE_MAIN_SCRIPT" ] || [ ! -f "$SOURCE_UTILS_SCRIPT" ]; then
    print_info "Source files not found locally, attempting download (curl | sh mode)..."

    # Create a temporary directory
    # Try mktemp first, fallback for systems without it (less secure)
    TEMP_DOWNLOAD_DIR=$(mktemp -d 2>/dev/null || mktemp -d -t 'cpm-install.XXXXXX') 
    if [ -z "$TEMP_DOWNLOAD_DIR" ] || [ ! -d "$TEMP_DOWNLOAD_DIR" ]; then
        print_error "Failed to create temporary directory."
        exit 1
    fi
    log_debug "Created temporary download directory: $TEMP_DOWNLOAD_DIR"

    # Define GitHub Raw URLs (adjust branch if needed)
    base_url="https://raw.githubusercontent.com/BLTGV/claude-mcp-manager/main/src"
    main_script_url="${base_url}/claude-mcp-manager"
    utils_script_url="${base_url}/utils.sh"

    # Define paths for downloaded files
    downloaded_main_script="${TEMP_DOWNLOAD_DIR}/claude-mcp-manager"
    downloaded_utils_script="${TEMP_DOWNLOAD_DIR}/utils.sh"

    # Download main script
    print_info "Downloading main script from $main_script_url..."
    if ! curl -fsSL "$main_script_url" -o "$downloaded_main_script"; then
        print_error "Failed to download main script from $main_script_url"
        # Cleanup is handled by trap
        exit 1
    fi

    # Download utils script
    print_info "Downloading utils script from $utils_script_url..."
    if ! curl -fsSL "$utils_script_url" -o "$downloaded_utils_script"; then
        print_error "Failed to download utils script from $utils_script_url"
        # Cleanup is handled by trap
        exit 1
    fi

    # Update source paths to point to the downloaded files
    SOURCE_MAIN_SCRIPT="$downloaded_main_script"
    SOURCE_UTILS_SCRIPT="$downloaded_utils_script"
    print_success "Required source files downloaded successfully."
else
    print_info "Found source files locally."
fi

# Now SOURCE_MAIN_SCRIPT and SOURCE_UTILS_SCRIPT point to the correct files
# either locally or in the temporary directory.
print_success "Source files are ready."

# 2. Determine Installation Directories
INSTALL_LIB_DIR=""
INSTALL_BIN_DIR=""

print_info "Determining installation location..."

# Try system-wide first (/usr/local)
# Check if we *can* write to the parent /usr/local/lib, then attempt mkdir
if [ -w "$(dirname "$DEFAULT_LIB_DIR")" ]; then
    if mkdir -p "$DEFAULT_LIB_DIR" 2>/dev/null || [ -d "$DEFAULT_LIB_DIR" ]; then # Check if already exists too
        if [ -w "$DEFAULT_LIB_DIR" ] && [ -w "$DEFAULT_BIN_DIR" ] && path_contains "$DEFAULT_BIN_DIR"; then
            print_info "Found writable system location: $DEFAULT_BIN_DIR (in PATH)"
            INSTALL_LIB_DIR="$DEFAULT_LIB_DIR"
            INSTALL_BIN_DIR="$DEFAULT_BIN_DIR"
        else
             print_warning "System lib directory ($DEFAULT_LIB_DIR) might be writable, but bin directory ($DEFAULT_BIN_DIR) is not writable or not in PATH."
        fi
    else
        print_warning "Could not create or write to system lib directory: $DEFAULT_LIB_DIR"
    fi
else
    print_info "System location /usr/local/lib is not writable. Checking user location."
fi

# If system-wide failed or isn't ideal, try user-local (~/.local)
if [ -z "$INSTALL_BIN_DIR" ]; then
    print_info "Checking user-local location: $USER_BIN_DIR"
    # Ensure ~/.local/lib exists or can be created
    if mkdir -p "$(dirname "$USER_LIB_DIR")" 2>/dev/null && [ -w "$(dirname "$USER_LIB_DIR")" ]; then
        if mkdir -p "$USER_LIB_DIR" 2>/dev/null || [ -d "$USER_LIB_DIR" ]; then # Check if exists
            if [ -w "$USER_LIB_DIR" ]; then
                # Ensure ~/.local/bin exists or can be created
                if mkdir -p "$USER_BIN_DIR" 2>/dev/null && [ -w "$USER_BIN_DIR" ]; then
                    INSTALL_LIB_DIR="$USER_LIB_DIR"
                    INSTALL_BIN_DIR="$USER_BIN_DIR"
                    if path_contains "$USER_BIN_DIR"; then
                        print_info "Using user-local location: $USER_BIN_DIR (in PATH)"
                    else
                        print_warning "Using user-local location: $USER_BIN_DIR"
                        print_warning "This directory is NOT in your PATH. You need to add it."
                        echo_bold "Add the following line to your shell profile (~/.profile, ~/.bashrc, ~/.zshrc, etc.):"
                        printf "  export PATH=\"%s:\$PATH\"\n" "$USER_BIN_DIR"
                        echo "Then restart your shell or run: . ~/.your_profile_file"
                    fi
                else
                    print_warning "Could not write to user bin directory: $USER_BIN_DIR"
                fi
            else
                 print_warning "Could not write to user lib directory: $USER_LIB_DIR"
            fi
        else
             print_warning "Could not create user lib directory: $USER_LIB_DIR"
        fi
    else
         print_warning "Could not write to user lib directory parent: $(dirname "$USER_LIB_DIR")"
    fi
fi

# If still no location, fail
if [ -z "$INSTALL_BIN_DIR" ] || [ -z "$INSTALL_LIB_DIR" ]; then
    print_error "Could not determine a suitable installation location."
    print_info "Checked /usr/local and $HOME/.local. Ensure you have write permissions or manually create the directories and add the bin directory to your PATH."
    exit 1
fi

# Calculate target paths using the potentially updated SOURCE_* variables
TARGET_MAIN_SCRIPT_PATH="$INSTALL_LIB_DIR/$(basename "$SOURCE_MAIN_SCRIPT")"
TARGET_UTILS_SCRIPT_PATH="$INSTALL_LIB_DIR/$(basename "$SOURCE_UTILS_SCRIPT")"
SYMLINK_PATH="$INSTALL_BIN_DIR/$APP_NAME"

printf "\n" # Add a newline before the details section
echo_bold "Installation Details:"
printf "  Library Directory: %s\n" "$INSTALL_LIB_DIR"
printf "  Binary Directory:  %s\n" "$INSTALL_BIN_DIR"
printf "  Command Symlink:   %s\n" "$SYMLINK_PATH"
printf "\n"

print_info "Proceeding with installation..."

# 3. Check Dependencies
check_dependencies

# 3.5 Check for and Uninstall Previous Version
print_info "Checking for existing claude-mcp-manager installation..."
EXISTING_CMD_PATH=$(command -v claude-mcp-manager)
if [ -n "$EXISTING_CMD_PATH" ] && [ -x "$EXISTING_CMD_PATH" ]; then
    print_info "Found existing installation at: $EXISTING_CMD_PATH"
    print_info "Attempting to run automatic uninstall of previous version (will not remove config)..."
    if "$EXISTING_CMD_PATH" uninstall --yes; then
        print_success "Previous version uninstalled successfully."
    else
        print_warning "Uninstall command failed (previous version might be broken or uninstall failed)."
        print_warning "Proceeding with installation, but manual cleanup might be needed later."
    fi
else
    print_info "No previous installation found or command not executable."
fi
printf "\n"

# 4. Ensure Library Directory Exists (already checked writability earlier)
print_info "Ensuring library directory exists: $INSTALL_LIB_DIR"
mkdir -p "$INSTALL_LIB_DIR"
if [ $? -ne 0 ]; then
    print_error "Failed to create library directory: $INSTALL_LIB_DIR"
    exit 1
fi

# 5. Copy Files
print_info "Copying script files..."
cp "$SOURCE_MAIN_SCRIPT" "$TARGET_MAIN_SCRIPT_PATH"
if [ $? -ne 0 ]; then
    print_error "Failed to copy main script to $TARGET_MAIN_SCRIPT_PATH"
    exit 1
fi
cp "$SOURCE_UTILS_SCRIPT" "$TARGET_UTILS_SCRIPT_PATH"
if [ $? -ne 0 ]; then
    print_error "Failed to copy utils script to $TARGET_UTILS_SCRIPT_PATH"
    exit 1
fi

# 6. Set Permissions
print_info "Setting execute permissions..."
chmod +x "$TARGET_MAIN_SCRIPT_PATH"
if [ $? -ne 0 ]; then
    print_error "Failed to set execute permission on $TARGET_MAIN_SCRIPT_PATH"
    exit 1 # Permissions are critical
fi
# Utils script doesn't need execute, just read
chmod 644 "$TARGET_UTILS_SCRIPT_PATH"

# 7. Create Symlink
print_info "Creating symlink: $SYMLINK_PATH"
# Remove existing symlink if it exists, in case of reinstall (should be handled by pre-uninstall now)
rm -f "$SYMLINK_PATH"
ln -s "$TARGET_MAIN_SCRIPT_PATH" "$SYMLINK_PATH"
if [ $? -ne 0 ]; then
    print_error "Failed to create symlink at $SYMLINK_PATH"
    print_info "You might need to run this installer with sudo if installing to /usr/local/bin, or check permissions."
    # Attempt cleanup
    rm -f "$TARGET_MAIN_SCRIPT_PATH" "$TARGET_UTILS_SCRIPT_PATH"
    exit 1
fi

# 8. Initial Setup Hint
print_info "Running initial setup check (this will create config directories if needed)..."
# Use command -v to find the installed command, then execute it
if installed_cmd=$(command -v "$APP_NAME") && [ -n "$installed_cmd" ]; then
    if "$installed_cmd" server list > /dev/null 2>&1; then
        print_success "Initial setup check completed."
    else
        print_warning "Initial setup check command failed. You may need to run '$APP_NAME help' manually."
    fi
else
     print_warning "Could not find installed command '$APP_NAME' in PATH to run setup check."
fi

# 9. Completion Message
print_success "Installation complete!"
printf "You can now run the command: %b%s%b\n" "$COLOR_BOLD" "$APP_NAME" "$COLOR_RESET"
if ! path_contains "$INSTALL_BIN_DIR"; then
    print_warning "Remember to add $INSTALL_BIN_DIR to your PATH if you haven't already."
fi
printf "Run '%b%s help%b' to get started.\n" "$COLOR_BOLD" "$APP_NAME" "$COLOR_RESET"

printf "\n"
print_info "To use the command in your *current* shell session, you may need to:"
printf "  1. Run: %bhash -r%b\n" "$COLOR_BOLD" "$COLOR_RESET"
printf "  2. Or, open a new terminal tab/window.\n"

# Cleanup function is called automatically via trap
exit 0 