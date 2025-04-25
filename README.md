# Claude MCP Manager

A command-line tool for macOS to define, manage, and switch between different sets of `mcpServers` configurations (profiles) for the Claude Desktop application.

## Goal

The Claude desktop app stores its configuration, including the `mcpServers` endpoints, in a JSON file. This tool allows you to define multiple named configuration profiles (e.g., 'default', 'staging', 'dev') and easily switch the active `mcpServers` block in the Claude configuration file without manually editing it each time. It also automatically restarts Claude to apply the changes.

## Requirements

*   **macOS:** The script relies on macOS-specific paths (`~/Library/Application Support/Claude/`) and commands (`killall`, `open`). **It will not work on Windows or Linux.**
*   **jq:** The script uses `jq` to parse and manipulate JSON files. Install it if you haven't already:
    ```bash
    brew install jq
    ```

## Installation

### Quick Install (Recommended)

_(macOS Only)_ Run the following command in your terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/BLTGV/claude-mcp-manager/main/setup.sh | sh -s -- --install
```

This will download the script and run its installer directly.

### Manual Installation

1.  Save the `setup.sh` script to your machine (e.g., download it from the repository).
2.  Make it executable: `chmod +x setup.sh`
3.  Run the script's installer from the directory where you saved it:
    ```bash
    ./setup.sh --install
    ```
    This will copy the script to `/usr/local/bin/claude-mcp-manager` (using `sudo` if needed) and make it available in your PATH.

You only need to run the installation once. Subsequently, you can use the `claude-mcp-manager` command directly.

## How it Works

*   **Configuration Directory:** Named configurations are stored as `.json` files in `~/.config/claude/`.
*   **Target File:** The script modifies the official Claude config file at `~/Library/Application Support/Claude/claude_desktop_config.json`.
*   **`mcpServers` Key:** The script *only* reads and writes the `mcpServers` key and its value. Any other keys in your source `.json` files are ignored, and any other keys in the target Claude config file are preserved.
*   **Tracking (`loaded` file):** The script keeps track of the *name* of the currently active configuration in `~/.config/claude/loaded`.
*   **Backup (`last.json`):** Before applying a new configuration, the script saves the *current* `mcpServers` block from the target file into `~/.config/claude/last.json`, allowing easy rollback.
*   **First Run:** If `~/.config/claude/default.json` doesn't exist when you first run the script (after installation), it will try to copy the `mcpServers` block from your existing Claude configuration into `default.json`.

## Usage

_(Note: The specific commands for server/profile management are defined in the PRD and will be implemented.)_

### Activate a Profile

Use the `claude-mcp-manager <profile_name>` command. If no name is given, it defaults to `default`.

```bash
# Switch to 'work' profile
claude-mcp-manager work

# Switch to 'default' profile
claude-mcp-manager default
# or
claude-mcp-manager 
```

### List Profiles & Servers

```bash
# List available profiles and the current one
claude-mcp-manager -l 
# or 
claude-mcp-manager --list 
# or 
claude-mcp-manager profile list

# List available server definitions
claude-mcp-manager server list 
```

### Revert to Previous Configuration

Switch back to the configuration that was active *before* the last switch:

```bash
claude-mcp-manager last
```

### Manage Servers & Profiles (Examples - based on PRD)

```bash
# Add a server definition from a file
claude-mcp-manager server add my-new-server --file ./path/to/server.json

# Add a server reference to a profile
claude-mcp-manager profile add work my-new-server

# Edit a profile
claude-mcp-manager profile edit work 
```

## Uninstall

To uninstall, simply remove the script and the configuration directory:

```bash
sudo rm /usr/local/bin/claude-mcp-manager
rm -rf ~/.config/claude/
``` 