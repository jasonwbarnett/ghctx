# ghctx - Shell-Local GitHub Context Switching

A race-condition-free solution for managing multiple GitHub accounts with the `gh` CLI.

## The Problem

The official `gh` CLI (v2.40.0+) supports multiple accounts via `gh auth switch`, but it modifies **global state**. Extensions like [gh-context](https://github.com/automationpi/gh-context) and [gh-profile](https://github.com/gabe565/gh-profile) have the same issue.

This causes race conditions when you have multiple terminal sessions:

```
Shell A (in ~/work/repo)        Shell B (in ~/personal/repo)
────────────────────────        ────────────────────────────
cd into repo
auto-switches to "work"
                                cd into repo
                                auto-switches to "personal"
git push
  → uses "personal" token       ← WRONG IDENTITY
```

Shell B's context switch affected Shell A because they share global state.

## How ghctx Solves This

Instead of calling `gh auth switch` (which modifies `~/.config/gh/hosts.yml`), ghctx sets `GH_TOKEN` and `GH_HOST` as **environment variables** local to your shell session.

- Each shell maintains independent state
- Concurrent shells can use different identities safely
- Tokens are retrieved on-demand from `gh`'s secure storage (keyring)

## Installation

### Prerequisites

- [GitHub CLI](https://cli.github.com/) (`gh`) v2.40.0 or later
- Bash or Zsh

### Quick Install

```bash
# Download the script
curl -fsSL https://raw.githubusercontent.com/jasonwbarnett/ghctx/main/gh-context.sh \
  -o ~/.config/gh/gh-context.sh

# Add to your shell config
echo 'source ~/.config/gh/gh-context.sh' >> ~/.bashrc   # bash
echo 'source ~/.config/gh/gh-context.sh' >> ~/.zshrc    # zsh
```

### Manual Install

1. Copy `gh-context.sh` to `~/.config/gh/gh-context.sh`
2. Add to your `.bashrc` or `.zshrc`:

```bash
source ~/.config/gh/gh-context.sh
```

3. **(Optional)** Enable auto-switching based on `.ghcontext` files:

```bash
# For bash
PROMPT_COMMAND="_ghctx_auto; $PROMPT_COMMAND"

# For zsh
precmd_functions+=(_ghctx_auto)
```

4. **(Optional)** Show active context in your prompt:

```bash
# Add to PS1
PS1='$(ghctx_prompt)'"$PS1"
```

## Setup

First, log in to each GitHub account you want to use:

```bash
# Log in to your first account
gh auth login

# Log in to additional accounts (same or different hosts)
gh auth login --hostname github.com
gh auth login --hostname github.mycompany.com
```

Then create named contexts:

```bash
# Create a context from current gh auth
ghctx new personal

# Switch gh auth to another account and create another context
gh auth switch --user work-username
ghctx new work
```

## Usage

### Commands

| Command | Description |
|---------|-------------|
| `ghctx list` | List all contexts |
| `ghctx new <name>` | Create context from current `gh auth` |
| `ghctx use <name>` | Switch this shell to context |
| `ghctx delete <name>` | Remove a context |
| `ghctx bind <name>` | Create `.ghcontext` in repo root |
| `ghctx unbind` | Remove `.ghcontext` from repo root |
| `ghctx current` | Show this shell's active context |
| `ghctx clear` | Unset context (use default `gh auth`) |

### Examples

```bash
# List available contexts
$ ghctx list
Contexts:
  personal (alice@github.com)
  work * (alice-corp@github.mycompany.com)

* = active in this shell

# Switch context in current shell
$ ghctx use personal
Switched to 'personal' (alice@github.com) [this shell only]

# Bind a repo to always use a specific context
$ cd ~/work/company-repo
$ ghctx bind work
Bound repo to 'work' (~/work/company-repo/.ghcontext)
Tip: Add .ghcontext to .gitignore

# Check current context
$ ghctx current
Active: work (alice-corp@github.mycompany.com)
Repo binding: work (in /Users/alice/work/company-repo/.ghcontext)
```

### Auto-Switching

When you enable auto-switching and bind repos to contexts, ghctx automatically switches when you `cd` into a bound repository:

```bash
$ cd ~/personal/my-project    # has .ghcontext containing "personal"
Switched to 'personal' (alice@github.com) [this shell only]

$ cd ~/work/company-repo      # has .ghcontext containing "work"
Switched to 'work' (alice-corp@github.mycompany.com) [this shell only]
```

## How It Works

### Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                     gh's secure storage                      │
│  (keyring: stores tokens for all logged-in accounts)         │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ gh auth token --user X --hostname Y
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                    ghctx context files                       │
│  ~/.config/gh/contexts/                                      │
│    ├── personal.ctx  (HOST=github.com, USER=alice)          │
│    └── work.ctx      (HOST=enterprise.com, USER=alice-corp) │
└─────────────────────────────────────────────────────────────┘
                              │
                              │ ghctx use <name>
                              ▼
┌─────────────────┐     ┌─────────────────┐     ┌─────────────────┐
│    Shell A      │     │    Shell B      │     │    Shell C      │
│                 │     │                 │     │                 │
│ GH_TOKEN=xxx    │     │ GH_TOKEN=yyy    │     │ (no context)    │
│ GH_HOST=gh.com  │     │ GH_HOST=ent.com │     │ uses default    │
│ _GH_CTX=personal│     │ _GH_CTX=work    │     │                 │
└─────────────────┘     └─────────────────┘     └─────────────────┘
        │                       │                       │
        ▼                       ▼                       ▼
   git push               git push               git push
   (as alice)          (as alice-corp)        (as default)
```

### Key Design Decisions

1. **Environment variables for isolation**: `GH_TOKEN` and `GH_HOST` are process-local, so each shell is independent.

2. **Tokens retrieved on-demand**: Context files only store hostname and username. Tokens are fetched from `gh`'s secure storage when switching, so credentials stay protected.

3. **Must be sourced**: Unlike `gh` extensions that run as subprocesses, this script must be sourced so it can modify your shell's environment.

## Comparison with Alternatives

| Feature | `gh auth switch` | [gh-context](https://github.com/automationpi/gh-context) | [gh-profile](https://github.com/gabe565/gh-profile) | **ghctx** |
|---------|-----------------|------------|------------|-----------|
| Race-condition safe | No | No | No* | **Yes** |
| Per-shell isolation | No | No | With direnv | **Yes** |
| Auto-switch on cd | No | Yes | With direnv | **Yes** |
| Secure token storage | Yes | Yes | Yes | **Yes** |
| Install method | Built-in | `gh extension` | `gh extension` | Source script |

*gh-profile can be race-safe if combined with direnv, but requires additional setup.

## Troubleshooting

### "Cannot get token for user@host"

The user isn't logged in via `gh auth`. Fix:

```bash
gh auth login --hostname <host>
```

### Context doesn't persist after opening new terminal

This is expected behavior. Each shell starts fresh. Use auto-switching with `.ghcontext` files for persistence:

```bash
cd ~/your/repo
ghctx bind <context-name>
```

### Git operations use wrong identity

1. Verify gh is your git credential helper:
   ```bash
   git config --global credential.helper
   # Should show: !/usr/bin/gh auth git-credential
   ```

2. Check your active context:
   ```bash
   ghctx current
   ```

3. Verify the token is set:
   ```bash
   echo $GH_TOKEN | head -c 10
   ```

### Auto-switching not working

Ensure you added the hook to your shell config **after** sourcing the script:

```bash
# .bashrc
source ~/.config/gh/gh-context.sh
PROMPT_COMMAND="_ghctx_auto; $PROMPT_COMMAND"

# .zshrc
source ~/.config/gh/gh-context.sh
precmd_functions+=(_ghctx_auto)
```

## Contributing

Contributions welcome! Please open an issue or PR.

## License

MIT
