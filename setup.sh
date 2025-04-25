#!/bin/sh

# Script to switch Claude MCP server configuration
# Usage: claude-mcp-switch [config_name | -l | --list | -u | --uninstall]

# --- Configuration ---
# Script paths
SCRIPT_NAME="claude-mcp-switch"
SCRIPT_PATH="/usr/local/bin/$SCRIPT_NAME"

# Configuration paths
CONFIG_DIR="$HOME/.config/claude"
APP_SUPPORT_DIR="$HOME/Library/Application Support/Claude"
TARGET_CONFIG="$APP_SUPPORT_DIR/claude_desktop_config.json"
LOADED_FILE="$CONFIG_DIR/loaded"
DEFAULT_CONFIG="$CONFIG_DIR/default.json"
LAST_CONFIG="$CONFIG_DIR/last.json"

# --- Colors and Formatting ---
C_RESET='\033[0m'
C_GREEN='\033[0;32m'
C_RED='\033[0;31m'
C_YELLOW='\033[0;33m'
C_BLUE='\033[0;34m'
C_BOLD='\033[1m'

# --- Helper Functions ---
echo_info() { echo "${C_BLUE}INFO:${C_RESET} $1"; }
echo_success() { echo "${C_GREEN}✓ SUCCESS:${C_RESET} $1"; }
echo_warning() { echo "${C_YELLOW}WARN:${C_RESET} $1"; }
echo_error() { echo "${C_RED}✗ ERROR:${C_RESET} $1" >&2; }

# --- Dependency Check ---
if ! command -v jq >/dev/null; then
  echo_error "This script requires 'jq' for JSON processing"
  echo "      Please install jq with: ${C_BOLD}brew install jq${C_RESET}"
  exit 1
fi
if ! command -v pgrep >/dev/null; then
  echo_error "This script requires 'pgrep' for checking running processes."
  echo "      It's usually part of standard macOS installations. Check your PATH or installation."
  exit 1
fi

# --- Installation Logic ---
INSTALL_URL="https://raw.githubusercontent.com/BLTGV/claude-mcp-config-switcher/main/setup.sh"

if [ "$1" = "--install" ] || [ ! -f "$SCRIPT_PATH" ]; then
  echo_info "Installing ${C_BOLD}$SCRIPT_NAME${C_RESET} to ${C_BOLD}$SCRIPT_PATH${C_RESET}..."
  # Create bin directory if it doesn't exist
  if [ ! -d "/usr/local/bin" ]; then
    if [ -w "/usr/local" ]; then
       mkdir -p "/usr/local/bin"
    else
       echo_warning "Requires administrator privileges to create /usr/local/bin"
       sudo mkdir -p "/usr/local/bin"
    fi
    if [ ! -d "/usr/local/bin" ]; then
        echo_error "Failed to create directory /usr/local/bin."
        exit 1
    fi
  fi

  # Download script content to bin directory
  if [ -w "/usr/local/bin" ]; then
    if ! command -v curl >/dev/null; then echo_error "curl is required for installation."; exit 1; fi
    if curl -fsSL "$INSTALL_URL" -o "$SCRIPT_PATH"; then
      chmod +x "$SCRIPT_PATH"
    else
      echo_error "Failed to download script from $INSTALL_URL"
      rm -f "$SCRIPT_PATH"
      exit 1
    fi
  else
    echo_warning "Installation requires administrator privileges"
    if ! command -v curl >/dev/null; then echo_error "curl is required for installation."; exit 1; fi
    if sudo sh -c "curl -fsSL '$INSTALL_URL' -o '$SCRIPT_PATH' && chmod +x '$SCRIPT_PATH'"; then
      : # Using colon as a no-op, success message printed below
    else
      echo_error "Failed to download script or set permissions using sudo."
      sudo rm -f "$SCRIPT_PATH" # Attempt cleanup
      exit 1
    fi
  fi

  echo_success "Installation complete. You can now run ${C_BOLD}$SCRIPT_NAME${C_RESET} from anywhere."

  if [ "$1" = "--install" ]; then
    exit 0
  fi
fi

# --- Main Script Logic ---

# Create config directory if it doesn't exist
if [ ! -d "$CONFIG_DIR" ]; then
  echo_info "Creating configuration directory: ${C_BOLD}$CONFIG_DIR${C_RESET}"
  mkdir -p "$CONFIG_DIR"
fi

# Function to extract mcpServers from source to target
extract_mcpservers() {
  source_file="$1"
  target_file="$2"

  # Extract mcpServers from source
  MCP_SERVERS=$(jq '.mcpServers' "$source_file")

  if [ ! -f "$target_file" ]; then
    # Create new file with just the mcpServers key
    echo "{\"mcpServers\": $MCP_SERVERS}" >"$target_file"
  else
    # Update existing file preserving other keys
    TEMP_FILE=$(mktemp)
    jq ".mcpServers = $MCP_SERVERS" "$target_file" >"$TEMP_FILE"
    mv "$TEMP_FILE" "$target_file"
  fi
}

# Function to list available configurations
list_configs() {
  echo "${C_BOLD}Available configurations:${C_RESET}"
  CONFIG_FOUND=false
  ls -1 "$CONFIG_DIR" | grep '\.json$' | sed 's/\.json$//' | grep -v "^last$" | while read -r config; do
    CONFIG_FOUND=true
    if jq -e '.mcpServers' "$CONFIG_DIR/$config.json" >/dev/null 2>&1; then
      echo "  ${C_GREEN}$config${C_RESET}"
    else
      echo "  ${C_YELLOW}$config${C_RESET} (invalid: missing mcpServers key)"
    fi
  done

  if ! $CONFIG_FOUND; then
    echo "  (No user configurations found in $CONFIG_DIR)"
  fi

  if [ -f "$LAST_CONFIG" ]; then
      if jq -e '.mcpServers' "$LAST_CONFIG" >/dev/null 2>&1; then
        echo "  ${C_BLUE}last${C_RESET} (previous configuration)"
      fi
  fi

  # Show currently loaded config
  if [ -f "$LOADED_FILE" ]; then
    CURRENT=$(cat "$LOADED_FILE")
    echo ""
    echo "${C_BOLD}Currently loaded:${C_RESET} ${C_GREEN}$CURRENT${C_RESET}"
  else
     echo ""
     echo "(No configuration currently loaded according to $LOADED_FILE)"
  fi
}

# Function to validate JSON has mcpServers key
validate_config() {
  config_file="$1"
  if ! jq -e '.mcpServers' "$config_file" >/dev/null 2>&1; then
    return 1
  fi
  return 0
}

# --- Argument Handling ---
# Handle list argument
if [ "$1" = "-l" ] || [ "$1" = "--list" ]; then
  list_configs
  exit 0
fi

# If no argument provided, use default config
if [ $# -eq 0 ]; then
  CONFIG_NAME="default"
  echo_info "No configuration specified, using 'default'."
else
  CONFIG_NAME="$1"
fi

# --- First Run Setup ---
if [ ! -f "$DEFAULT_CONFIG" ] && [ -f "$TARGET_CONFIG" ]; then
  echo_info "First run detected. Attempting to save current settings as ${C_BOLD}default.json${C_RESET}"
  if validate_config "$TARGET_CONFIG"; then
    extract_mcpservers "$TARGET_CONFIG" "$DEFAULT_CONFIG"
    echo "default" >"$LOADED_FILE"
    echo_success "Saved current mcpServers to default.json"
  else
    echo_warning "Current Claude configuration (${TARGET_CONFIG}) is missing the 'mcpServers' key."
    echo_warning "Cannot automatically create default.json. Please create it manually."
    # Don't exit, allow script to continue if user specifies another config
  fi
fi

# --- Configuration Validation and Switching Logic ---

# Check if source configuration exists
if [ "$CONFIG_NAME" != "last" ]; then
  SOURCE_CONFIG="$CONFIG_DIR/$CONFIG_NAME.json"
  if [ ! -f "$SOURCE_CONFIG" ]; then
    echo_error "Configuration file ${C_BOLD}$CONFIG_NAME.json${C_RESET} not found in $CONFIG_DIR"
    list_configs
    exit 1
  fi
  if ! validate_config "$SOURCE_CONFIG"; then
    echo_error "Configuration ${C_BOLD}$CONFIG_NAME.json${C_RESET} doesn't have the 'mcpServers' key."
    exit 1
  fi
else
  # Handle "last" config
  SOURCE_CONFIG="$LAST_CONFIG"
  if [ ! -f "$SOURCE_CONFIG" ]; then
    echo_error "No previous configuration (last.json) found."
    list_configs
    exit 1
  fi
  if ! validate_config "$SOURCE_CONFIG"; then
    echo_error "Previous configuration (last.json) doesn't have the 'mcpServers' key."
    exit 1
  fi
  echo_info "Switching to last used configuration..."
fi

# Validate target config exists and has mcpServers (or create if missing)
if [ ! -f "$TARGET_CONFIG" ]; then
  echo_warning "Claude configuration file not found at ${C_BOLD}$TARGET_CONFIG${C_RESET}"
  echo_warning "Make sure Claude is installed and has run once."
  echo_info "Creating a new config file with mcpServers from ${C_BOLD}$CONFIG_NAME.json${C_RESET}..."
  MCP_SERVERS=$(jq '.mcpServers' "$SOURCE_CONFIG")
  # Ensure the directory exists before writing
  mkdir -p "$(dirname "$TARGET_CONFIG")"
  if echo "{\"mcpServers\": $MCP_SERVERS}" >"$TARGET_CONFIG"; then
    echo_success "Created ${TARGET_CONFIG}"
    echo "$CONFIG_NAME" > "$LOADED_FILE"
    touch "$LOADED_FILE"
    # Claude isn't running yet, so just open it
    echo_info "Opening Claude application..."
    open -a "Claude"
    exit 0
  else
    echo_error "Failed to create ${TARGET_CONFIG}"
    exit 1
  fi
elif ! validate_config "$TARGET_CONFIG"; then
  echo_warning "Current Claude configuration (${TARGET_CONFIG}) doesn't have 'mcpServers' key."
  echo_warning "Will add/replace the mcpServers block from ${C_BOLD}$CONFIG_NAME.json${C_RESET}."
  # Allow switch to proceed, it will add/overwrite the key
fi

# --- Check if Switch is Needed ---
NEED_TO_SWITCH=true
UPDATE_LAST=true
CONFIG_DISPLAY_NAME=$CONFIG_NAME

if [ -f "$LOADED_FILE" ]; then
  CURRENT=$(cat "$LOADED_FILE")
  # Determine the effective source config file for comparison
  EFFECTIVE_SOURCE_CONFIG=$SOURCE_CONFIG
  if [ "$CONFIG_NAME" = "last" ]; then
      CONFIG_DISPLAY_NAME="last (effectively $CURRENT?)" # Placeholder, actual name found later if needed
  fi

  # Compare current mcpServers content in target with the effective source
  SOURCE_MCP=$(jq -c '.mcpServers' "$EFFECTIVE_SOURCE_CONFIG" 2>/dev/null || echo "SOURCE_ERROR")
  TARGET_MCP=$(jq -c '.mcpServers' "$TARGET_CONFIG" 2>/dev/null || echo "TARGET_ERROR")

  if [ "$SOURCE_MCP" = "SOURCE_ERROR" ]; then
    echo_warning "Could not read mcpServers from source config ($EFFECTIVE_SOURCE_CONFIG). Proceeding with switch."
  elif [ "$TARGET_MCP" = "TARGET_ERROR" ]; then
     echo_warning "Could not read mcpServers from target config ($TARGET_CONFIG). Proceeding with switch."
  elif [ "$SOURCE_MCP" = "$TARGET_MCP" ]; then
      # Content matches, now check if the source file is newer than the loaded marker
      if [ "$(ls -t "$EFFECTIVE_SOURCE_CONFIG" "$LOADED_FILE" 2>/dev/null | head -1)" = "$LOADED_FILE" ]; then
          echo_info "Already using configuration matching ${C_BOLD}$CONFIG_DISPLAY_NAME${C_RESET}."
          NEED_TO_SWITCH=false

          # Check if Claude is already running
          if pgrep -x "Claude" > /dev/null; then
            echo_info "Claude is already running. No action needed."
            exit 0 # Exit successfully, no need to switch or open
          else
            # Claude not running, let script continue to the final open step
             echo_info "Claude is not running."
          fi
      else
          echo_info "Updating to newer version of configuration ${C_BOLD}$CONFIG_DISPLAY_NAME${C_RESET}..."
          UPDATE_LAST=false # Don't update last when just refreshing the same config
      fi
  fi
fi

# --- Perform Switch (if needed) ---
if [ "$NEED_TO_SWITCH" = true ]; then
  # Save current config as 'last' before switching
  if [ -f "$TARGET_CONFIG" ] && validate_config "$TARGET_CONFIG" && [ "$UPDATE_LAST" = true ]; then
    # Don't overwrite last if we're loading last (or if source content matches last)
    LAST_MCP=$(jq -c '.mcpServers' "$LAST_CONFIG" 2>/dev/null || echo "LAST_ERROR")
    TARGET_MCP_FOR_LAST=$(jq -c '.mcpServers' "$TARGET_CONFIG") # Assume target is valid here

    if [ "$CONFIG_NAME" != "last" ] && [ "$TARGET_MCP_FOR_LAST" != "$LAST_MCP" ]; then
      echo_info "Saving current mcpServers to ${C_BOLD}last.json${C_RESET}"
      extract_mcpservers "$TARGET_CONFIG" "$LAST_CONFIG"
    fi
  fi

  # Apply the new configuration - only update mcpServers key
  echo_info "Switching configuration to ${C_BOLD}$CONFIG_NAME${C_RESET}..."
  MCP_SERVERS=$(jq '.mcpServers' "$SOURCE_CONFIG")
  TEMP_FILE=$(mktemp)
  # Use jq to safely update the target file
  if jq ".mcpServers = \$new_mcp" --argjson new_mcp "$MCP_SERVERS" "$TARGET_CONFIG" > "$TEMP_FILE" && mv "$TEMP_FILE" "$TARGET_CONFIG"; then
      : # Success, continue
  else
      echo_error "Failed to update mcpServers in ${TARGET_CONFIG}"
      rm -f "$TEMP_FILE" # Clean up temp file on failure
      exit 1
  fi

  # Track the currently loaded config
  TRACK_NAME=$CONFIG_NAME
  if [ "$CONFIG_NAME" = "last" ] && [ -f "$LAST_CONFIG" ]; then
    # Figure out the actual name of the last config if possible
    LAST_MCP_CONTENT=$(jq -c '.mcpServers' "$LAST_CONFIG")
    ACTUAL_NAME=""
    for f in "$CONFIG_DIR"/*.json; do
      f_base=$(basename "$f" .json)
      if [ "$f_base" != "last" ]; then
        # Compare mcpServers content
        F_MCP_CONTENT=$(jq -c '.mcpServers' "$f" 2>/dev/null || echo "")
        if [ "$F_MCP_CONTENT" = "$LAST_MCP_CONTENT" ]; then
          ACTUAL_NAME=$f_base
          break
        fi
      fi
    done
    if [ -n "$ACTUAL_NAME" ]; then
      echo_info "(Last configuration matched: ${C_BOLD}$ACTUAL_NAME${C_RESET})"
      TRACK_NAME=$ACTUAL_NAME
    else
      echo_info "(Could not find a named config matching last.json)"
      TRACK_NAME="last"
    fi
  fi
  echo "$TRACK_NAME" >"$LOADED_FILE"
  touch "$LOADED_FILE"

  # Terminate Claude if it's running to apply changes
  echo_info "Closing Claude application (if running)..."
  killall "Claude" 2>/dev/null

  # Wait for Claude process to disappear (more robust than sleep)
  ATTEMPTS=0
  MAX_ATTEMPTS=5 # Wait up to 5 seconds
  echo -n "Waiting for Claude to close..."
  while pgrep -x "Claude" > /dev/null && [ $ATTEMPTS -lt $MAX_ATTEMPTS ]; do
    sleep 0.5 # Check more frequently
    echo -n "."
    ATTEMPTS=$((ATTEMPTS + 2)) # Increment faster if needed
  done
  echo "" # Newline after dots

  if [ $ATTEMPTS -ge $MAX_ATTEMPTS ] && pgrep -x "Claude" > /dev/null; then
    echo_warning "Claude process may not have terminated fully."
  fi

  echo_success "Configuration switched successfully!"

fi # End of if NEED_TO_SWITCH

# --- Final Step: Ensure Claude is Running ---
echo_info "Ensuring Claude application is running..."
open -a "Claude"

echo_info "Done."
exit 0 # Explicit successful exit
