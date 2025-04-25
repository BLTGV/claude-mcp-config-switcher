# Claude MCP Config Switcher

A simple command-line tool for macOS to quickly switch between different `mcpServers` configurations for the Claude desktop application.

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
curl -fsSL https://raw.githubusercontent.com/BLTGV/claude-mcp-config-switcher/main/setup.sh | sh -s -- --install
```

This will download the script and run its installer directly.

### Manual Installation

1.  Save the `setup.sh` script to your machine (e.g., download it from the repository).
2.  Make it executable: `chmod +x setup.sh`
3.  Run the script's installer from the directory where you saved it:
    ```bash
    ./setup.sh --install
    ```
    This will copy the script to `/usr/local/bin/claude-mcp-switch` (using `sudo` if needed) and make it available in your PATH.

You only need to run the installation once. Subsequently, you can use the `claude-mcp-switch` command directly.

## How it Works

*   **Configuration Directory:** Named configurations are stored as `.json` files in `~/.config/claude/`.
*   **Target File:** The script modifies the official Claude config file at `~/Library/Application Support/Claude/claude_desktop_config.json`.
*   **`mcpServers` Key:** The script *only* reads and writes the `mcpServers` key and its value. Any other keys in your source `.json` files are ignored, and any other keys in the target Claude config file are preserved.
*   **Tracking (`loaded` file):** The script keeps track of the *name* of the currently active configuration in `~/.config/claude/loaded`.
*   **Backup (`last.json`):** Before applying a new configuration, the script saves the *current* `mcpServers` block from the target file into `~/.config/claude/last.json`, allowing easy rollback.
*   **First Run:** If `~/.config/claude/default.json` doesn't exist when you first run the script (after installation), it will try to copy the `mcpServers` block from your existing Claude configuration into `default.json`.

## Usage

### 1. Create Configuration Files

Manually create `.json` files in the `~/.config/claude/` directory. Each file should represent a configuration profile and *must* contain at least the `mcpServers` key.

**Example: `~/.config/claude/work_profile.json`** (Configures filesystem and GitHub tools)

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-filesystem",
        "/Users/your_username/Documents/Work", // Allow access to Work folder
        "/Users/your_username/Projects"        // Allow access to Projects folder
      ],
      "disabled": false
    },
    "github": {
      "command": "npx", // Assuming installed via npm/npx
      "args": [
        "-y",
        "@modelcontextprotocol/server-github" // Use correct package name if different
      ],
      "env": {
        "GITHUB_PERSONAL_ACCESS_TOKEN": "YOUR_GITHUB_PAT_HERE" // Remember to replace this!
      },
      "disabled": false
    }
  },
  "someOtherKey": "This might control other Claude settings"
}
```

**Example: `~/.config/claude/personal_profile.json`** (Configures only filesystem for personal folders)

```json
{
  "mcpServers": {
    "filesystem": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-filesystem",
        "/Users/your_username/Desktop",      // Allow access to Desktop
        "/Users/your_username/Downloads",    // Allow access to Downloads
        "/Users/your_username/Pictures"      // Allow access to Pictures
      ],
      "disabled": false
    }
    // GitHub server is omitted (or could be explicitly disabled)
  }
}
```

### 2. Switch Configurations

Use the `claude-mcp-switch` command followed by the name of the configuration file (without the `.json` extension).

*   **Switch to `staging`:**
    ```bash
    claude-mcp-switch staging
    ```
*   **Switch to `default`:**
    ```bash
    claude-mcp-switch default
    ```
    or simply:
    ```bash
    claude-mcp-switch
    ```
    (Defaults to `default` if no name is provided)

The script will update the Claude config file and restart the Claude application.

### 3. List Available Configurations

See which configurations are available and which one is currently loaded:

```bash
claude-mcp-switch -l
# or
claude-mcp-switch --list
```

Output might look like:

```
Available configurations:
  default
  staging
  dev (invalid: missing mcpServers key)

Currently loaded: staging
```

### 4. Revert to Previous Configuration

Switch back to the configuration that was active *before* the current one:

```bash
claude-mcp-switch last
```

## Uninstall

To uninstall, simply remove the script and the configuration directory:

```bash
sudo rm /usr/local/bin/claude-mcp-switch
rm -rf ~/.config/claude/
``` 