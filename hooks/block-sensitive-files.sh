#!/bin/bash
# PreToolUse hook to block access to sensitive files
# Prevents Claude Code from reading/writing environment files, credentials, keys, etc.

set -euo pipefail

# Read JSON input from stdin
input=$(cat)

# Extract tool name and inputs
tool_name=$(echo "$input" | jq -r '.tool_name // ""')
file_path=$(echo "$input" | jq -r '.tool_input.file_path // ""')
bash_command=$(echo "$input" | jq -r '.tool_input.command // ""')
glob_pattern=$(echo "$input" | jq -r '.tool_input.pattern // ""')
glob_path=$(echo "$input" | jq -r '.tool_input.path // ""')

# Define blocked patterns
# These are filenames and patterns that should never be accessed
declare -a BLOCKED_FILES=(
    # Environment files
    ".env"
    ".env.local"
    ".env.fish"
    ".env.development"
    ".env.production"
    ".env.test"
    ".env.staging"
    ".envrc"

    # Secret/credential files
    "secret.yml"
    "secrets.yml"
    "secrets.yaml"
    "secret.json"
    "secrets.json"
    "credentials.json"
    "credentials.yml"
    ".credentials"
    "service-account.json"
    "service-account-key.json"
    ".npmrc"
    ".pypirc"

    # SSH keys
    "id_rsa"
    "id_rsa.pub"
    "id_ed25519"
    "id_ed25519.pub"
    "id_ecdsa"
    "id_ecdsa.pub"
    "id_dsa"
    "known_hosts"
    "authorized_keys"

    # AWS/Cloud configs
    "credentials"
    "config"
    "application_default_credentials.json"

    # Database configs
    ".pgpass"
    ".my.cnf"
    ".netrc"
    ".htpasswd"

    # API/Token files
    "api_key.txt"
    "apikey.txt"
    ".vault-token"

    # Other sensitive
    ".git-credentials"
    "master.key"
    "credentials.yml.enc"
)

declare -a BLOCKED_EXTENSIONS=(
    ".pem"
    ".key"
    ".p12"
    ".pfx"
    ".token"
    ".keystore"
    ".jks"
)

declare -a BLOCKED_DIRS=(
    ".aws"
    ".ssh"
    ".gnupg"
    ".azure"
    ".docker"
)

# Function to check if a path is sensitive
is_sensitive_path() {
    local path="$1"

    if [[ -z "$path" ]]; then
        return 1
    fi

    # Get just the filename
    local filename=$(basename "$path")

    # Check exact filename matches
    for blocked in "${BLOCKED_FILES[@]}"; do
        if [[ "$filename" == "$blocked" ]]; then
            echo "File '$filename' is in blocked files list"
            return 0
        fi
    done

    # Check extension patterns
    for ext in "${BLOCKED_EXTENSIONS[@]}"; do
        if [[ "$filename" == *"$ext" ]]; then
            echo "File '$filename' has blocked extension '$ext'"
            return 0
        fi
    done

    # Check if path contains blocked directories
    for dir in "${BLOCKED_DIRS[@]}"; do
        if [[ "$path" == *"/$dir/"* ]] || [[ "$path" == *"/$dir" ]]; then
            echo "Path contains blocked directory '$dir'"
            return 0
        fi
    done

    # Check for secret/credential patterns in filename
    if [[ "$filename" =~ (secret|credential|password|passwd|token)s? ]]; then
        echo "Filename contains sensitive keyword: '$filename'"
        return 0
    fi

    return 1
}

# Function to deny access
deny_access() {
    local reason="$1"
    jq -n \
        --arg reason "[Sensitive File Protection] $reason" \
        '{"decision": "block", "reason": $reason}'
    exit 2
}

# Check file operation tools (Read, Write, Edit, MultiEdit)
if [[ "$tool_name" =~ ^(Read|Write|Edit|MultiEdit)$ ]] && [[ -n "$file_path" ]]; then
    if reason=$(is_sensitive_path "$file_path"); then
        deny_access "$reason"
    fi
fi

# Check Bash commands for file access
if [[ "$tool_name" == "Bash" ]] && [[ -n "$bash_command" ]]; then
    # Extract potential file paths from the command
    # Look for common file-reading commands followed by paths

    # Check for direct file references in command
    for blocked in "${BLOCKED_FILES[@]}"; do
        if [[ "$bash_command" =~ $blocked ]]; then
            deny_access "Bash command references blocked file: $blocked"
        fi
    done

    # Check for blocked extensions
    for ext in "${BLOCKED_EXTENSIONS[@]}"; do
        if [[ "$bash_command" =~ [[:space:]][^[:space:]]*\\$ext([[:space:]]|$) ]]; then
            deny_access "Bash command references file with blocked extension: $ext"
        fi
    done

    # Check for sensitive keywords in file paths
    if [[ "$bash_command" =~ (\.env|secret|credential|id_rsa|\.aws|\.ssh) ]]; then
        deny_access "Bash command may access sensitive files or directories"
    fi
fi

# Check Glob patterns
if [[ "$tool_name" == "Glob" ]]; then
    if [[ -n "$glob_pattern" ]]; then
        for blocked in "${BLOCKED_FILES[@]}"; do
            if [[ "$glob_pattern" =~ $blocked ]]; then
                deny_access "Glob pattern targets blocked file: $blocked"
            fi
        done
    fi

    if [[ -n "$glob_path" ]]; then
        if reason=$(is_sensitive_path "$glob_path"); then
            deny_access "Glob base path: $reason"
        fi
    fi
fi

# Check Grep tool
if [[ "$tool_name" == "Grep" ]] && [[ -n "$glob_path" ]]; then
    if reason=$(is_sensitive_path "$glob_path"); then
        deny_access "Grep target: $reason"
    fi
fi

# Allow the operation
exit 0
