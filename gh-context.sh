# gh-context.sh - Shell-specific GitHub context switching (no race conditions)
# Source this file in your .bashrc or .zshrc:
#   source ~/.config/gh/gh-context.sh
#
# Contexts are shell-local via environment variables, not global state.

GH_CTX_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/gh/contexts"
mkdir -p "$GH_CTX_DIR"

# Current shell's active context (not shared with other shells)
_GH_CTX_CURRENT=""

ghctx() {
  local cmd="${1:-}"
  case "$cmd" in
    list)    _ghctx_list ;;
    new)     shift; _ghctx_new "$@" ;;
    use)     shift; _ghctx_use "$@" ;;
    delete)  shift; _ghctx_delete "$@" ;;
    bind)    shift; _ghctx_bind "$@" ;;
    unbind)  _ghctx_unbind ;;
    current) _ghctx_current ;;
    clear)   _ghctx_clear ;;
    *)       _ghctx_help ;;
  esac
}

_ghctx_help() {
  cat <<'EOF'
ghctx - Shell-local GitHub context switching

Usage:
  ghctx list              List all contexts
  ghctx new <name>        Create context from current gh auth
  ghctx use <name>        Switch this shell to context (sets GH_TOKEN/GH_HOST)
  ghctx delete <name>     Remove a context
  ghctx bind <name>       Create .ghcontext in repo root
  ghctx unbind            Remove .ghcontext from repo root
  ghctx current           Show this shell's active context
  ghctx clear             Unset context (use default gh auth)

Auto-switching:
  Add to your shell config after sourcing this file:
    PROMPT_COMMAND="_ghctx_auto; $PROMPT_COMMAND"  # bash
    precmd_functions+=(_ghctx_auto)                # zsh

How it works:
  Unlike gh-context extension, this sets GH_TOKEN and GH_HOST as environment
  variables in your current shell. Each shell has independent state, so
  concurrent shells won't interfere with each other.
EOF
}

_ghctx_list() {
  local ctx_files=("$GH_CTX_DIR"/*.ctx)
  if [[ ! -e "${ctx_files[0]}" ]]; then
    echo "No contexts found. Create one with: ghctx new <name>"
    return 0
  fi

  echo "Contexts:"
  for f in "$GH_CTX_DIR"/*.ctx; do
    local name host user
    name="$(basename "$f" .ctx)"
    host="$(grep '^HOST=' "$f" | cut -d= -f2)"
    user="$(grep '^USER=' "$f" | cut -d= -f2)"

    local marker=""
    [[ "$name" == "$_GH_CTX_CURRENT" ]] && marker=" *"
    printf "  %s%s (%s@%s)\n" "$name" "$marker" "$user" "$host"
  done

  [[ -n "$_GH_CTX_CURRENT" ]] && echo -e "\n* = active in this shell"
}

_ghctx_new() {
  local name="$1"
  [[ -z "$name" ]] && { echo "Usage: ghctx new <name>"; return 1; }

  local ctx_file="$GH_CTX_DIR/$name.ctx"
  [[ -f "$ctx_file" ]] && { echo "Context '$name' already exists"; return 1; }

  local host="${GH_HOST:-github.com}"
  local user
  user="$(gh api user --hostname "$host" --jq .login 2>/dev/null)" || {
    echo "Failed to get current user. Are you logged in? (gh auth login)"
    return 1
  }

  # Verify we can get a token for this user
  if ! gh auth token --hostname "$host" --user "$user" > /dev/null 2>&1; then
    echo "Cannot retrieve token for $user@$host"
    return 1
  fi

  cat > "$ctx_file" <<EOF
HOST=$host
USER=$user
EOF

  echo "Created context '$name' ($user@$host)"
}

_ghctx_use() {
  local name="$1"
  [[ -z "$name" ]] && { echo "Usage: ghctx use <name>"; return 1; }

  local ctx_file="$GH_CTX_DIR/$name.ctx"
  [[ -f "$ctx_file" ]] || { echo "Context '$name' not found"; return 1; }

  local host user token
  host="$(grep '^HOST=' "$ctx_file" | cut -d= -f2)"
  user="$(grep '^USER=' "$ctx_file" | cut -d= -f2)"

  # Get token from gh's secure storage (keyring)
  token="$(gh auth token --hostname "$host" --user "$user" 2>/dev/null)" || {
    echo "Cannot get token for $user@$host"
    echo "Try: gh auth login --hostname $host"
    return 1
  }

  # Set environment variables for THIS shell only
  export GH_TOKEN="$token"
  export GH_HOST="$host"
  _GH_CTX_CURRENT="$name"

  echo "Switched to '$name' ($user@$host) [this shell only]"
}

_ghctx_clear() {
  unset GH_TOKEN
  unset GH_HOST
  _GH_CTX_CURRENT=""
  echo "Cleared context (using default gh auth)"
}

_ghctx_current() {
  if [[ -z "$_GH_CTX_CURRENT" ]]; then
    echo "No context active in this shell (using default gh auth)"
    [[ -n "$GH_TOKEN" ]] && echo "Note: GH_TOKEN is set from elsewhere"
  else
    local ctx_file="$GH_CTX_DIR/$_GH_CTX_CURRENT.ctx"
    local host user
    host="$(grep '^HOST=' "$ctx_file" | cut -d= -f2)"
    user="$(grep '^USER=' "$ctx_file" | cut -d= -f2)"
    echo "Active: $_GH_CTX_CURRENT ($user@$host)"
  fi

  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || true
  if [[ -n "$root" && -f "$root/.ghcontext" ]]; then
    echo "Repo binding: $(cat "$root/.ghcontext") (in $root/.ghcontext)"
  fi
}

_ghctx_delete() {
  local name="$1"
  [[ -z "$name" ]] && { echo "Usage: ghctx delete <name>"; return 1; }

  local ctx_file="$GH_CTX_DIR/$name.ctx"
  [[ -f "$ctx_file" ]] || { echo "Context '$name' not found"; return 1; }

  rm -f "$ctx_file"

  # Clear if we deleted the active context
  [[ "$_GH_CTX_CURRENT" == "$name" ]] && _ghctx_clear

  echo "Deleted context '$name'"
}

_ghctx_bind() {
  local name="$1"
  [[ -z "$name" ]] && { echo "Usage: ghctx bind <name>"; return 1; }

  local ctx_file="$GH_CTX_DIR/$name.ctx"
  [[ -f "$ctx_file" ]] || { echo "Context '$name' not found"; return 1; }

  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "Not in a git repository"
    return 1
  }

  echo "$name" > "$root/.ghcontext"
  echo "Bound repo to '$name' ($root/.ghcontext)"
  echo "Tip: Add .ghcontext to .gitignore"
}

_ghctx_unbind() {
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "Not in a git repository"
    return 1
  }

  if [[ -f "$root/.ghcontext" ]]; then
    rm -f "$root/.ghcontext"
    echo "Removed repo binding"
  else
    echo "No binding found"
  fi
}

# Auto-apply based on .ghcontext file
# Add to PROMPT_COMMAND (bash) or precmd (zsh)
_ghctx_auto() {
  local root
  root="$(git rev-parse --show-toplevel 2>/dev/null)" || return 0

  if [[ -f "$root/.ghcontext" ]]; then
    local bound
    bound="$(cat "$root/.ghcontext")"

    # Only switch if different from current
    if [[ "$bound" != "$_GH_CTX_CURRENT" ]]; then
      _ghctx_use "$bound"
    fi
  fi
}

# Optional: Show context in prompt
# Usage: PS1='$(ghctx_prompt)$ '
ghctx_prompt() {
  [[ -n "$_GH_CTX_CURRENT" ]] && echo "[gh:$_GH_CTX_CURRENT] "
}

# Helper to list context names (for completions)
_ghctx_names() {
  local ctx_files=("$GH_CTX_DIR"/*.ctx)
  [[ -e "${ctx_files[0]}" ]] || return 0
  for f in "$GH_CTX_DIR"/*.ctx; do
    basename "$f" .ctx
  done
}

# Bash completion
if [[ -n "$BASH_VERSION" ]]; then
  _ghctx_completions() {
    local cur="${COMP_WORDS[COMP_CWORD]}"
    local prev="${COMP_WORDS[COMP_CWORD-1]}"

    case "$prev" in
      ghctx)
        COMPREPLY=($(compgen -W "list new use delete bind unbind current clear" -- "$cur"))
        ;;
      use|delete|bind)
        COMPREPLY=($(compgen -W "$(_ghctx_names)" -- "$cur"))
        ;;
    esac
  }
  complete -F _ghctx_completions ghctx
fi

# Zsh completion
if [[ -n "$ZSH_VERSION" ]]; then
  _ghctx() {
    local -a subcmds contexts
    subcmds=(
      'list:List all contexts'
      'new:Create context from current gh auth'
      'use:Switch this shell to context'
      'delete:Remove a context'
      'bind:Create .ghcontext in repo root'
      'unbind:Remove .ghcontext from repo root'
      'current:Show this shell'\''s active context'
      'clear:Unset context (use default gh auth)'
    )

    if (( CURRENT == 2 )); then
      _describe 'command' subcmds
    elif (( CURRENT == 3 )); then
      case "${words[2]}" in
        use|delete|bind)
          contexts=($(_ghctx_names))
          _describe 'context' contexts
          ;;
      esac
    fi
  }
  compdef _ghctx ghctx
fi
