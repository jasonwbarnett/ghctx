#!/usr/bin/env bash
# ghctx installer
set -euo pipefail

INSTALL_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/gh"
SCRIPT_NAME="gh-context.sh"

main() {
  echo "Installing ghctx..."

  # Check for gh CLI
  if ! command -v gh &> /dev/null; then
    echo "Error: GitHub CLI (gh) is not installed."
    echo "Install it from: https://cli.github.com/"
    exit 1
  fi

  # Check gh version
  local gh_version
  gh_version=$(gh --version | head -1 | grep -oE '[0-9]+\.[0-9]+\.[0-9]+')
  local major minor
  major=$(echo "$gh_version" | cut -d. -f1)
  minor=$(echo "$gh_version" | cut -d. -f2)

  if [[ "$major" -lt 2 ]] || [[ "$major" -eq 2 && "$minor" -lt 40 ]]; then
    echo "Warning: gh version $gh_version detected. Version 2.40.0+ recommended for multi-account support."
  fi

  # Create directory
  mkdir -p "$INSTALL_DIR"

  # Determine script location (local or remote)
  local script_path
  script_path="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/$SCRIPT_NAME"

  if [[ -f "$script_path" ]]; then
    # Local install
    cp "$script_path" "$INSTALL_DIR/$SCRIPT_NAME"
  else
    # Remote install
    echo "Downloading $SCRIPT_NAME..."
    curl -fsSL "https://raw.githubusercontent.com/jasonwbarnett/ghctx/main/$SCRIPT_NAME" \
      -o "$INSTALL_DIR/$SCRIPT_NAME"
  fi

  chmod 644 "$INSTALL_DIR/$SCRIPT_NAME"

  echo "Installed to: $INSTALL_DIR/$SCRIPT_NAME"
  echo ""
  echo "Add the following to your shell config:"
  echo ""

  # Detect shell
  local shell_name
  shell_name=$(basename "$SHELL")

  case "$shell_name" in
    bash)
      cat <<'EOF'
# ~/.bashrc
source ~/.config/gh/gh-context.sh

# Optional: auto-switch based on .ghcontext files
PROMPT_COMMAND="_ghctx_auto; $PROMPT_COMMAND"

# Optional: show context in prompt
PS1='$(ghctx_prompt)'"$PS1"
EOF
      ;;
    zsh)
      cat <<'EOF'
# ~/.zshrc
source ~/.config/gh/gh-context.sh

# Optional: auto-switch based on .ghcontext files
precmd_functions+=(_ghctx_auto)

# Optional: show context in prompt
PS1='$(ghctx_prompt)'"$PS1"
EOF
      ;;
    *)
      cat <<EOF
# Add to your shell config:
source ~/.config/gh/gh-context.sh
EOF
      ;;
  esac

  echo ""
  echo "Then restart your shell or run: source ~/.config/gh/gh-context.sh"
  echo ""
  echo "Quick start:"
  echo "  ghctx new personal    # Create context from current gh auth"
  echo "  ghctx list            # List all contexts"
  echo "  ghctx use personal    # Switch to context"
  echo "  ghctx bind personal   # Bind current repo to context"
}

main "$@"
