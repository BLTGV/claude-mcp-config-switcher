#!/usr/bin/env bash

# Utility functions for claude-mcp-manager

# === Colors ===
# Usage: print_color "$COLOR_RED" "This is red text"
COLOR_RESET='\033[0m'
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[0;33m'
COLOR_BLUE='\033[0;34m'
COLOR_BOLD='\033[1m'

# Internal function to handle actual printing
_print_color() {
    local color="$1"
    local message="$2"
    # Check if stdout is a terminal
    if [ -t 1 ]; then
        echo -e "${color}${message}${COLOR_RESET}" >&1
    else
        echo "${message}" >&1 # No colors if not a TTY
    fi
}

# Internal function to print to stderr (for errors/warnings)
_print_color_stderr() {
    local color="$1"
    local message="$2"
    # Use fd 2 (stderr)
    if [ -t 2 ]; then
        echo -e "${color}${message}${COLOR_RESET}" >&2
    else
        echo "${message}" >&2 # No colors if not a TTY
    fi
}

# === Public Print Functions ===

# Usage: print_error "Something went wrong."
print_error() {
    # Errors go to stderr
    _print_color_stderr "$COLOR_RED" "ERROR: $1"
}

# Usage: exit_with_error "Error message" [exit_code]
exit_with_error() {
  local message="$1"
  local exit_code="${2:-1}" # Default exit code is 1
  log_error "$message" # Log the error message
  # print_error is called by log_error if level is sufficient
  exit "$exit_code"
}

# Usage: print_success "Operation successful."
print_success() {
    _print_color "$COLOR_GREEN" "SUCCESS: $1"
}

# Usage: print_warning "This is a warning."
print_warning() {
    # Warnings go to stderr
    _print_color_stderr "$COLOR_YELLOW" "WARNING: $1"
}

# Usage: print_info "Just some information."
print_info() {
    _print_color "$COLOR_BLUE" "INFO: $1"
}

# Usage: print_bold "Important Heading"
print_bold() {
    _print_color "$COLOR_BOLD" "$1"
}

# === Logging ===
LOG_FILE="${HOME}/.config/claude/claude-mcp-manager.log"

# Define Log Levels (numerical, lower is more verbose)
LOG_LEVEL_DEBUG=0
LOG_LEVEL_INFO=1
LOG_LEVEL_WARN=2
LOG_LEVEL_ERROR=3

# Set current log level (Default: INFO)
# TODO: Make this configurable via ENV var or flag
# CURRENT_LOG_LEVEL=${LOG_LEVEL_INFO}

# Determine current log level
if [[ -n "${MCP_LOG_LEVEL}" ]]; then
    log_level_upper=$(echo "${MCP_LOG_LEVEL}" | tr '[:lower:]' '[:upper:]') # Convert to uppercase portably
    case "${log_level_upper}" in
        DEBUG) CURRENT_LOG_LEVEL=$LOG_LEVEL_DEBUG ;;
        INFO)  CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO ;;
        WARN)  CURRENT_LOG_LEVEL=$LOG_LEVEL_WARN ;;
        ERROR) CURRENT_LOG_LEVEL=$LOG_LEVEL_ERROR ;;
        *)     CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO ; echo "WARNING: Invalid MCP_LOG_LEVEL '${MCP_LOG_LEVEL}'. Defaulting to INFO." >&2 ;;
    esac
else
    CURRENT_LOG_LEVEL=$LOG_LEVEL_INFO # Default to INFO if variable is not set
fi

# Ensure log file exists and has correct permissions
if [ ! -e "$LOG_FILE" ]; then
    touch "$LOG_FILE" || { echo "ERROR: Failed to create log file: $LOG_FILE" >&2; }
    chmod 600 "$LOG_FILE" || { echo "ERROR: Failed to set permissions on log file: $LOG_FILE" >&2; }
fi

log_message() {
    local level_name="$1"
    local message="$2"
    local level_num
    local level_name_upper # Variable to hold uppercase level name

    # Map level name to number
    level_name_upper=$(echo "${level_name}" | tr '[:lower:]' '[:upper:]')
    case "${level_name_upper}" in # Use the uppercase variable
        DEBUG) level_num=$LOG_LEVEL_DEBUG ;;
        INFO)  level_num=$LOG_LEVEL_INFO ;;
        WARN)  level_num=$LOG_LEVEL_WARN ;;
        ERROR) level_num=$LOG_LEVEL_ERROR ;;
        *)     level_num=$LOG_LEVEL_INFO ; message="[INVALID LEVEL: ${level_name}] ${message}" ;;
    esac

    local timestamp
    timestamp=$(date '+%Y-%m-%d %H:%M:%S')
    # Always write to log file
    echo "${timestamp} [${level_name_upper}] ${message}" >> "$LOG_FILE" || { echo "WARNING: Failed to write to log file: $LOG_FILE" >&2; }

    # Print to terminal if level is sufficient
    if [ "$level_num" -ge "$CURRENT_LOG_LEVEL" ]; then
        case "${level_name_upper}" in # Use the uppercase variable here too
            ERROR) print_error "$message" ;;
            WARN)  print_warning "$message" ;;
            INFO)  print_info "$message" ;;
            DEBUG) print_info "DEBUG: $message" ;;
            # SUCCESS is not a log level, use print_success directly
        esac
    fi
}

# Convenience log functions
log_debug() { log_message "DEBUG" "$1"; }
log_info()  { log_message "INFO" "$1"; }
log_warn()  { log_message "WARN" "$1"; }
log_error() { log_message "ERROR" "$1"; }

# === File/Directory Validation ===

# Usage: check_file_exists "/path/to/file"
check_file_exists() {
  if [ ! -f "$1" ]; then
    exit_with_error "File does not exist: $1"
  fi
}

# Usage: check_file_writable "/path/to/file"
check_file_writable() {
  check_file_exists "$1"
  if [ ! -w "$1" ]; then
    exit_with_error "File is not writable: $1"
  fi
}

# Usage: check_file_readable "/path/to/file"
check_file_readable() {
  check_file_exists "$1"
  if [ ! -r "$1" ]; then
    exit_with_error "File is not readable: $1"
  fi
}

# Usage: check_dir_exists "/path/to/dir"
check_dir_exists() {
  if [ ! -d "$1" ]; then
    exit_with_error "Directory does not exist: $1"
  fi
}

# Usage: check_dir_writable "/path/to/dir"
check_dir_writable() {
  check_dir_exists "$1"
  if [ ! -w "$1" ]; then
    exit_with_error "Directory is not writable: $1"
  fi
}

# Usage: validate_json_file "/path/to/file.json"
validate_json_file() {
  check_file_readable "$1"
  if ! jq . "$1" > /dev/null 2>&1; then
      exit_with_error "Invalid JSON in file: $1"
  fi
}

# Add other utilities below (path resolution, etc.)

# === Claude Process Management ===

CLAUDE_APP_NAME="Claude"

# Checks if the Claude application process is running.
# Returns 0 if running, 1 otherwise.
is_claude_running() {
    log_debug "Checking if ${CLAUDE_APP_NAME} process is running..."
    if pgrep -f "${CLAUDE_APP_NAME}" > /dev/null; then
        log_debug "${CLAUDE_APP_NAME} process found."
        return 0 # Process found
    else
        log_debug "${CLAUDE_APP_NAME} process not found."
        return 1 # Process not found
    fi
}

# Attempts to kill the Claude application process.
kill_claude() {
    log_info "Attempting to terminate ${CLAUDE_APP_NAME} process..."
    local pid
    pid=$(pgrep -f "${CLAUDE_APP_NAME}")

    if [ -z "$pid" ]; then
        log_info "${CLAUDE_APP_NAME} process not running, no need to kill."
        return 0
    fi

    log_debug "Found ${CLAUDE_APP_NAME} PID(s): ${pid}. Sending TERM signal."
    # Use kill directly on the PIDs found
    if kill ${pid} > /dev/null 2>&1; then
        log_debug "TERM signal sent. Waiting for process to exit..."
        # Wait up to 5 seconds for graceful shutdown
        local count=0
        while is_claude_running && [ $count -lt 5 ]; do
            sleep 1
            ((count++))
            log_debug "Still waiting for ${CLAUDE_APP_NAME} to exit... (${count}s)"
        done

        if ! is_claude_running; then
            log_info "${CLAUDE_APP_NAME} terminated gracefully."
            return 0
        else
            log_warn "${CLAUDE_APP_NAME} did not terminate gracefully after 5 seconds. Sending KILL signal."
            if kill -9 ${pid} > /dev/null 2>&1; then
                log_info "${CLAUDE_APP_NAME} terminated forcefully (KILL signal)."
                # Short pause after kill -9
                sleep 1 
                return 0
            else
                log_error "Failed to send KILL signal to ${CLAUDE_APP_NAME} PID(s): ${pid}. Manual intervention might be required."
                return 1
            fi
        fi
    else
        log_error "Failed to send TERM signal to ${CLAUDE_APP_NAME} PID(s): ${pid}. Process might already be gone or permissions issue."
        # Check if it's already gone
        if ! is_claude_running; then
            log_info "${CLAUDE_APP_NAME} seems to have terminated already."
            return 0
        fi
        return 1
    fi
}

# Starts the Claude application.
start_claude() {
    log_info "Attempting to start ${CLAUDE_APP_NAME}..."
    if open -a "${CLAUDE_APP_NAME}"; then
        log_info "${CLAUDE_APP_NAME} started successfully."
        # Add a small delay to allow the app to initialize
        sleep 2
        return 0
    else
        log_error "Failed to start ${CLAUDE_APP_NAME}. Is it installed in the standard Applications folder?"
        return 1
    fi
}

# Restarts the Claude application (kills if running, then starts).
restart_claude() {
    log_info "Attempting to restart ${CLAUDE_APP_NAME}..."
    if is_claude_running; then
        if ! kill_claude; then
            log_error "Failed to kill existing ${CLAUDE_APP_NAME} process. Aborting restart."
            return 1
        fi
        # Ensure it's fully stopped before restarting
        if is_claude_running; then
             log_error "${CLAUDE_APP_NAME} process still detected after kill attempt. Aborting restart."
             return 1
        fi
    else
        log_info "${CLAUDE_APP_NAME} is not running. Proceeding with start."
    fi

    if ! start_claude; then
        log_error "Failed to start ${CLAUDE_APP_NAME} during restart sequence."
        return 1
    fi

    log_info "${CLAUDE_APP_NAME} restart sequence completed."
    return 0
}

# === Secrets Management ===

# Loads variables from the .env file into the current environment
# Skips comments and empty lines.
load_dotenv() {
    local dotenv_file="${CONFIG_DIR}/.env"
    if [ ! -f "$dotenv_file" ]; then
        log_debug "Dotenv file not found: ${dotenv_file}. Skipping dotenv loading."
        return 0
    fi
    log_debug "Loading secrets from ${dotenv_file}"
    
    # Use process substitution to avoid subshell issues with variable scope
    # Read line by line, trim whitespace, skip comments/empty lines
    while IFS= read -r line || [ -n "$line" ]; do 
        # Remove leading/trailing whitespace (more portable than bash 4+ features)
        line=$(echo "$line" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        # Skip empty lines and comments
        if [ -z "$line" ] || [[ "$line" =~ ^# ]]; then
            continue
        fi
        # Export the variable. Handles basic VAR=value format.
        # Does not handle quotes or complex values perfectly, but ok for simple keys.
        if export "$line"; then
             # Extract var name for logging (safer than logging $line)
             local var_name=${line%%=*}
             log_debug "Exported variable: ${var_name} from dotenv file."
        else
             log_warn "Failed to export line from dotenv: $line"
        fi
    done < "$dotenv_file"
    log_debug "Finished loading secrets from ${dotenv_file}"
}

# Resolves placeholders like {{ENV:VAR}} or {{DOTENV:KEY}} within a JSON string.
# Placeholders MUST be the entire string value for a key (e.g., "apiKey": "{{ENV:API_KEY}}").
# It does NOT handle placeholders embedded within larger strings.
# WARNING: This function processes potentially sensitive data. Be careful with logging.
resolve_placeholders() {
    local input_json_string="$1"
    local resolved_json_string="$input_json_string"
    local placeholder
    local type
    local key
    local value
    local json_value

    # Use standard indexed arrays for Bash 3.2 compatibility
    local placeholder_keys=()
    local placeholder_values=()
    # Use a simple delimited string to track found keys portably
    local found_keys_string="|"

    log_debug "Attempting to resolve placeholders in JSON string (Bash 3.2 compatible)..." >&2

    # First pass: Find all unique placeholders and get resolved values
    # Use grep -o to find all potential matches
    local all_matches
    # Ensure grep gets the input string correctly via stdin
    # Use tr to replace newlines with a delimiter for looping
    all_matches=$(echo "$input_json_string" | grep -Eo '\{\{(ENV|DOTENV):([a-zA-Z0-9_]+)\}\}' | tr '\n' '|')
    
    # Save original IFS and set to delimiter
    local OLD_IFS="$IFS"
    IFS='|'
    # Process each match
    for placeholder in $all_matches; do
        # Restore IFS inside loop if needed, but likely not here
        # Handle potential empty fields if delimiter is at start/end
        if [ -z "$placeholder" ]; then continue; fi
        
        # Check if we already processed this specific placeholder string
        # Use grep for portable substring check
        # Add delimiters for exact match check
        if echo "$found_keys_string" | grep -qF "|${placeholder}|"; then
            continue
        fi
        # Mark as found
        found_keys_string="${found_keys_string}${placeholder}|"
        log_debug "Found unique placeholder: $placeholder" >&2

        # Extract type and key using parameter expansion for portability
        local temp_type_key
        temp_type_key="${placeholder#\{\{}" # Remove leading {{ -> TYPE:KEY}}
        type="${temp_type_key%%:*}"        # Remove first : and everything after -> TYPE
        key="${temp_type_key#*:}"          # Remove TYPE and first : -> KEY}}
        key="${key%%\}\}}"             # Remove trailing }} -> KEY
        
        value="" # Default to empty

        # Defensive check for extracted key/type
        if [ -z "$type" ] || [ -z "$key" ]; then
             log_warn "Failed to extract type/key from potential placeholder: $placeholder. Skipping." >&2
             continue
        fi

        case "$type" in
            ENV | DOTENV)
                # Still need eval to dynamically access env var named by $key
                # Use default expansion to avoid unbound variable errors if key DNE
                eval "value=\"\${$key:-}\""
                ;; 
            *)
                # This case should ideally not happen with the grep/sed patterns,
                # but handle defensively.
                log_warn "Invalid type extracted '$type' for placeholder: $placeholder. Replacing with null." >&2
                value="null"
               ;;
        esac

        # Determine the final JSON value (string or null)
        if [ "$value" == "null" ]; then
             log_warn "Unsupported type or forced null for $placeholder. Replacing with JSON null." >&2
             json_value="null"
        elif [ -z "$value" ]; then
            log_warn "Value for placeholder $placeholder is empty or not set. Replacing with JSON empty string." >&2
            json_value='""' # JSON empty string
        else
             log_debug "Resolved $placeholder to a value (length: ${#value}). Will substitute later." >&2
             # IMPORTANT: Do NOT log the actual value here!
             # Use jq to create a valid JSON string representation of the value
             json_value=$(jq -n --arg v "$value" '$v')
             if [ $? -ne 0 ] || [ -z "$json_value" ]; then
                 log_warn "jq failed to encode value for $placeholder. Replacing with null." >&2
                 json_value="null"
             fi
        fi
        
        # Store the placeholder and its resolved+escaped JSON value
        placeholder_keys+=("$placeholder")
        placeholder_values+=("$json_value")
    done
    # Restore IFS
    IFS="$OLD_IFS"
    # End of the loop for processing matches

    # Second pass: Apply replacements using sed
    log_debug "Applying ${#placeholder_keys[@]} substitution(s)..." >&2
    local i=0
    while [ "$i" -lt "${#placeholder_keys[@]}" ]; do
         local current_placeholder="${placeholder_keys[i]}"
         local current_json_value="${placeholder_values[i]}"
         # Construct the search pattern including the quotes from the original JSON
         # Escape quotes and potentially other special characters for sed basic regex
         local search_pattern_sed
         search_pattern_sed=$(printf '%s\n' "\"${current_placeholder}\"" | sed 's/[.[\]\\*^$]/\\&/g')
         
         # Use sed for replacement. Use ~ as delimiter to avoid issues with / in values.
         # The current_json_value is already a valid JSON string (quoted and escaped by jq).
         local temp_resolved_string
         temp_resolved_string=$(echo "$resolved_json_string" | sed "s~${search_pattern_sed}~${current_json_value}~g")
         
         # Check if sed command succeeded and actually changed the string
         if [ $? -eq 0 ] && [ "$temp_resolved_string" != "$resolved_json_string" ]; then
             resolved_json_string="$temp_resolved_string"
             log_debug "Replaced ${search_pattern_sed} in string." >&2
         else
             log_warn "sed replacement failed or made no change for pattern ${search_pattern_sed}. Status: $?" >&2
             # Potentially add more debugging here if needed
         fi

         i=$((i + 1)) # Increment index
    done

    log_debug "Final resolved string before returning: $resolved_json_string" >&2
    # Return the resolved string (hopefully valid JSON)
    echo "$resolved_json_string"
}

# Example logging (simple version, needs refinement for levels/timestamps)
# LOG_FILE="${HOME}/.config/claude/claude-mcp-manager.log"
# 
# log_message() {
#     local level="$1"
#     local message="$2"
#     local timestamp
#     timestamp=$(date '+%Y-%m-%d %H:%M:%S')
#     echo "${timestamp} [${level}] ${message}" >> "$LOG_FILE"
#     # Optionally print to terminal based on level/verbosity (not implemented yet)
# } 