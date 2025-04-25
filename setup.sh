#!/bin/sh

# Script to switch Claude MCP server configuration
# Usage: claude-mcp-switch [config_name | -l | --list | -u | --uninstall]

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

# Check if jq is installed
if ! command -v jq >/dev/null; then
  echo "Error: This script requires 'jq' for JSON processing"
  echo "Please install jq with: brew install jq"
  exit 1
fi

# Modified self-installation section
# Replace the self-installation check with this:

# Always check if we need to install
if [ "$1" = "--install" ] || [ ! -f "$SCRIPT_PATH" ]; then
  echo "Installing $SCRIPT_NAME to /usr/local/bin..."
  # Create bin directory if it doesn't exist
  if [ ! -d "/usr/local/bin" ]; then
    sudo mkdir -p "/usr/local/bin"
  fi

  # Copy script to bin directory with sudo if needed
  if [ -w "/usr/local/bin" ]; then
    cp "$0" "$SCRIPT_PATH"
    chmod +x "$SCRIPT_PATH"
  else
    echo "Installation requires administrator privileges"
    sudo cp "$0" "$SCRIPT_PATH"
    sudo chmod +x "$SCRIPT_PATH"
  fi

  echo "Installation complete. You can now run $SCRIPT_NAME from anywhere."

  # Exit if explicit installation was requested
  if [ "$1" = "--install" ]; then
    exit 0
  fi
fi

# Create config directory if it doesn't exist
if [ ! -d "$CONFIG_DIR" ]; then
  echo "Creating configuration directory: $CONFIG_DIR"
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
  echo "Available configurations:"
  ls -1 "$CONFIG_DIR" | grep '\.json$' | sed 's/\.json$//' | grep -v "^last$" | while read -r config; do
    # Verify if config has mcpServers key
    if jq -e '.mcpServers' "$CONFIG_DIR/$config.json" >/dev/null 2>&1; then
      echo "  $config"
    else
      echo "  $config (invalid: missing mcpServers key)"
    fi
  done

  # Show currently loaded config
  if [ -f "$LOADED_FILE" ]; then
    CURRENT=$(cat "$LOADED_FILE")
    echo ""
    echo "Currently loaded: $CURRENT"
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

# Handle list argument
if [ "$1" = "-l" ] || [ "$1" = "--list" ]; then
  list_configs
  exit 0
fi

# If no argument provided, use default config
if [ $# -eq 0 ]; then
  CONFIG_NAME="default"
else
  CONFIG_NAME="$1"
fi

# On first run, create default config if it doesn't exist
if [ ! -f "$DEFAULT_CONFIG" ] && [ -f "$TARGET_CONFIG" ]; then
  echo "First run detected. Extracting mcpServers to default.json"
  if validate_config "$TARGET_CONFIG"; then
    extract_mcpservers "$TARGET_CONFIG" "$DEFAULT_CONFIG"
    echo "default" >"$LOADED_FILE"
  else
    echo "Error: Current configuration doesn't have mcpServers key"
    echo "Please create a valid configuration manually in $CONFIG_DIR/default.json"
    exit 1
  fi
fi

# Check if source configuration exists (except for 'last' which is handled specially)
if [ "$CONFIG_NAME" != "last" ]; then
  SOURCE_CONFIG="$CONFIG_DIR/$CONFIG_NAME.json"
  if [ ! -f "$SOURCE_CONFIG" ]; then
    echo "Error: Configuration file '$CONFIG_NAME.json' not found in $CONFIG_DIR"
    list_configs
    exit 1
  fi

  # Validate source config
  if ! validate_config "$SOURCE_CONFIG"; then
    echo "Error: Configuration '$CONFIG_NAME.json' doesn't have mcpServers key"
    exit 1
  fi
else
  # Handle "last" config
  if [ ! -f "$LAST_CONFIG" ]; then
    echo "Error: No previous configuration found"
    list_configs
    exit 1
  fi

  # Validate last config
  if ! validate_config "$LAST_CONFIG"; then
    echo "Error: Last configuration doesn't have mcpServers key"
    exit 1
  fi

  SOURCE_CONFIG="$LAST_CONFIG"
fi

# Validate target config exists and has mcpServers
if [ ! -f "$TARGET_CONFIG" ]; then
  echo "Error: Claude configuration file not found at $TARGET_CONFIG"
  echo "Make sure Claude is installed and has been run at least once"
  exit 1
elif ! validate_config "$TARGET_CONFIG"; then
  echo "Warning: Current Claude configuration doesn't have mcpServers key"
  echo "Will create a new configuration with default values plus mcpServers"
  # Create a basic configuration with mcpServers
  MCP_SERVERS=$(jq '.mcpServers' "$SOURCE_CONFIG")
  echo "{\"mcpServers\": $MCP_SERVERS}" >"$TARGET_CONFIG"
else
  # Check if we're already using this config and it hasn't been modified
  NEED_TO_SWITCH=true
  UPDATE_LAST=true
  if [ -f "$LOADED_FILE" ]; then
    CURRENT=$(cat "$LOADED_FILE")
    if [ "$CURRENT" = "$CONFIG_NAME" ] && [ -f "$SOURCE_CONFIG" ]; then
      # Compare mcpServers content
      SOURCE_MCP=$(jq -c '.mcpServers' "$SOURCE_CONFIG")
      TARGET_MCP=$(jq -c '.mcpServers' "$TARGET_CONFIG")

      if [ "$SOURCE_MCP" = "$TARGET_MCP" ]; then
        # Compare file modification times using ls -t
        if [ "$(ls -t "$SOURCE_CONFIG" "$LOADED_FILE" | head -1)" = "$LOADED_FILE" ]; then
          echo "Already using '$CONFIG_NAME' configuration"
          NEED_TO_SWITCH=false
          exit 0
        else
          echo "Updating to newer version of '$CONFIG_NAME' configuration"
          # When updating the same config, don't update last
          UPDATE_LAST=false
        fi
      fi
    fi
  fi

  # Only continue if we need to switch
  if [ "$NEED_TO_SWITCH" = true ]; then
    # Save current config as 'last' before switching (if needed)
    if [ -f "$TARGET_CONFIG" ] && [ -f "$LOADED_FILE" ] && [ "$UPDATE_LAST" = true ]; then
      CURRENT=$(cat "$LOADED_FILE")
      # Don't overwrite last if we're loading last
      if [ "$CONFIG_NAME" != "last" ]; then
        echo "Saving current mcpServers to last.json"
        extract_mcpservers "$TARGET_CONFIG" "$LAST_CONFIG"
      fi
    fi

    # Apply the new configuration - only update mcpServers key
    echo "Switching to '$CONFIG_NAME' configuration"
    MCP_SERVERS=$(jq '.mcpServers' "$SOURCE_CONFIG")
    TEMP_FILE=$(mktemp)
    jq ".mcpServers = $MCP_SERVERS" "$TARGET_CONFIG" >"$TEMP_FILE"
    mv "$TEMP_FILE" "$TARGET_CONFIG"

    # Track the currently loaded config
    if [ "$CONFIG_NAME" = "last" ] && [ -f "$LAST_CONFIG" ]; then
      # Figure out the actual name of the last config
      ACTUAL_NAME=""
      for f in "$CONFIG_DIR"/*.json; do
        if [ "$f" != "$LAST_CONFIG" ]; then
          # Compare mcpServers content
          if [ "$(jq -c '.mcpServers' "$f")" = "$(jq -c '.mcpServers' "$LAST_CONFIG")" ]; then
            ACTUAL_NAME=$(basename "$f" .json)
            echo "$ACTUAL_NAME" >"$LOADED_FILE"
            echo "Actually loaded: $ACTUAL_NAME"
            break
          fi
        fi
      done
      # If no match found, just use "last"
      if [ -z "$ACTUAL_NAME" ]; then
        echo "last" >"$LOADED_FILE"
      fi
    else
      echo "$CONFIG_NAME" >"$LOADED_FILE"
    fi

    # Update the loaded file timestamp
    touch "$LOADED_FILE"

    # Restart Claude
    echo "Restarting Claude application..."
    killall "Claude" 2>/dev/null
    open -a "Claude"

    echo "Configuration switched successfully!"
  fi
fi
