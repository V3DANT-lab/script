```bash
#!/usr/bin/env bash
set -Eeuo pipefail

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
BACKUP_DIR="$CONFIG_DIR/backups"
PROJECT_DIR="$(pwd)"

info() { printf '\n[INFO] %s\n' "$*"; }
ok()   { printf '[ OK ] %s\n' "$*"; }
warn() { printf '[WARN] %s\n' "$*"; }

backup() {
    local file="$1"

    if [[ -f "$file" ]]; then
        mkdir -p "$BACKUP_DIR"
        cp -a "$file" \
            "$BACKUP_DIR/$(basename "$file").$(date +%Y%m%d-%H%M%S).bak"
        ok "Backed up $(basename "$file")"
    fi
}

append_once() {
    local file="$1"
    local value="$2"

    touch "$file"

    grep -Fqx "$value" "$file" 2>/dev/null || \
        printf '%s\n' "$value" >> "$file"
}

install_plugin() {
    local plugin="$1"

    if opencode plugin "$plugin" --global; then
        ok "Installed $plugin"
    else
        warn "Could not automatically install $plugin"
    fi
}

echo "============================================================"
echo "              OPENCODE POWER INSTALLER"
echo "============================================================"
echo
echo "This installer configures:"
echo "  • OpenCode"
echo "  • OpenCode Mem"
echo "  • Dynamic Context Pruning"
echo "  • EnvSitter Guard"
echo "  • Oh My OpenCode Slim"
echo "  • Background agents"
echo "  • Exa web search"
echo "  • OpenCode Notify"
echo "  • Obot MCP"
echo "  • AGENTS.md"
echo "  • Verification pipeline"
echo "  • Git worktree helper"
echo

# ------------------------------------------------------------
# Dependencies
# ------------------------------------------------------------

info "Checking dependencies..."

for command in curl git node npm; do
    if ! command -v "$command" >/dev/null 2>&1; then
        echo "[ERROR] Missing dependency: $command"
        exit 1
    fi
done

NODE_MAJOR="$(node -v | sed 's/^v//' | cut -d. -f1)"

if (( NODE_MAJOR < 20 )); then
    echo "[ERROR] Node.js 20+ is required."
    echo "Detected: Node.js $(node -v)"
    exit 1
fi

ok "Required dependencies found"

# ------------------------------------------------------------
# OpenCode
# ------------------------------------------------------------

info "Installing/updating OpenCode..."

npm install -g @opencode/cli@latest

if ! command -v opencode >/dev/null 2>&1; then
    echo "[ERROR] OpenCode installation failed."
    exit 1
fi

ok "OpenCode installed"
opencode --version || true

# ------------------------------------------------------------
# Configuration directories
# ------------------------------------------------------------

info "Preparing OpenCode directories..."

mkdir -p \
    "$CONFIG_DIR" \
    "$CONFIG_DIR/backups" \
    "$CONFIG_DIR/agents" \
    "$CONFIG_DIR/commands" \
    "$CONFIG_DIR/skills"

# Never destroy existing configuration.
backup "$CONFIG_DIR/opencode.json"
backup "$CONFIG_DIR/opencode.jsonc"

ok "OpenCode directories ready"

# ------------------------------------------------------------
# Plugins
# ------------------------------------------------------------

info "Installing OpenCode plugins..."

install_plugin "opencode-mem"
install_plugin "@chikage0o0/opencode-dcp"
install_plugin "envsitter-guard@latest"
install_plugin "opencode-notify"

# ------------------------------------------------------------
# Oh My OpenCode Slim
# ------------------------------------------------------------

info "Installing Oh My OpenCode Slim..."

if command -v bun >/dev/null 2>&1; then
    bunx oh-my-opencode-slim@latest install \
        --no-tui \
        --skills=yes \
        --background-subagents=yes
else
    npx oh-my-opencode-slim@latest install \
        --no-tui \
        --skills=yes \
        --background-subagents=yes
fi

ok "Oh My OpenCode Slim configured"

# ------------------------------------------------------------
# Shell configuration
# ------------------------------------------------------------

info "Configuring OpenCode environment..."

if [[ "${SHELL:-}" == */zsh ]]; then
    SHELL_RC="$HOME/.zshrc"
else
    SHELL_RC="$HOME/.bashrc"
fi

append_once "$SHELL_RC" \
    'export OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS=true'

append_once "$SHELL_RC" \
    'export OPENCODE_ENABLE_EXA=1'

export OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS=true
export OPENCODE_ENABLE_EXA=1

ok "Environment variables configured"

# ------------------------------------------------------------
# Obot
# ------------------------------------------------------------

echo
echo "============================================================"
echo "                  OBOT / GITHUB MCP"
echo "============================================================"
echo
echo "Enter your Obot MCP endpoint."
echo "Leave empty to configure Obot later."
echo

read -r -p "Obot MCP URL: " OBOT_URL

if [[ -n "$OBOT_URL" ]]; then
    if opencode mcp add obot --url "$OBOT_URL"; then
        ok "Obot MCP configured"
    else
        warn "Obot could not be registered automatically."
        echo
        echo "Run later:"
        echo "opencode mcp add obot --url \"$OBOT_URL\""
    fi
else
    warn "Obot skipped."
fi

# ------------------------------------------------------------
# AGENTS.md
# ------------------------------------------------------------

AGENTS="$PROJECT_DIR/AGENTS.md"

if [[ ! -f "$AGENTS" ]]; then

cat > "$AGENTS" <<'EOF'
# AGENTS.md

## Core Development Rules

Inspect existing code before changing it.

For substantial tasks:

1. Plan.
2. Implement.
3. Lint.
4. Type-check.
5. Test.
6. Build.
7. Run the application when possible.
8. Inspect errors.
9. Fix failures.
10. Repeat verification.

## Code

Prefer existing project architecture.

Do not unnecessarily:
- rewrite working code
- add dependencies
- duplicate functionality
- remove existing features

## Security

Never commit:

- `.env`
- `.env.*`
- API keys
- access tokens
- passwords
- private keys
- credentials

Use environment variables for secrets.

## Database

Before database changes:

1. Inspect the schema.
2. Inspect existing migrations.
3. Understand relationships.
4. Check affected queries.
5. Test the affected functionality.

Do not destroy existing data without explicit instruction.

## Git

Before committing:

- inspect `git status`
- inspect the diff
- check changed files
- check for secrets

## Verification

A task is not complete merely because it compiles.

Verify:

- lint
- typecheck
- tests
- build
- runtime behavior
- relevant APIs
- relevant database operations

## Worktrees

Use a Git worktree for large or risky changes when appropriate.

## Completion

Before declaring a task complete, report:

- changes made
- files changed
- verification performed
- remaining issues
EOF

    ok "Created AGENTS.md"

else
    warn "Existing AGENTS.md preserved"
fi

# ------------------------------------------------------------
# Verification script
# ------------------------------------------------------------

VERIFY="$PROJECT_DIR/verify.sh"

if [[ ! -f "$VERIFY" ]]; then

cat > "$VERIFY" <<'EOF'
#!/usr/bin/env bash

set -u

FAILED=0

run_check() {
    local name="$1"
    shift

    echo
    echo ">>> $name"

    if "$@"; then
        echo "[PASS] $name"
    else
        echo "[FAIL] $name"
        FAILED=1
    fi
}

echo "============================================================"
echo "                 PROJECT VERIFICATION"
echo "============================================================"

if [[ -f package.json ]]; then

    if npm run | grep -qE '(^|[[:space:]])lint($|[[:space:]])'; then
        run_check "Lint" npm run lint
    fi

    if npm run | grep -qE '(^|[[:space:]])typecheck($|[[:space:]])'; then
        run_check "Typecheck" npm run typecheck
    fi

    if npm run | grep -qE '(^|[[:space:]])test($|[[:space:]])'; then
        run_check "Tests" npm test
    fi

    if npm run | grep -qE '(^|[[:space:]])build($|[[:space:]])'; then
        run_check "Build" npm run build
    fi

else
    echo "[INFO] package.json not found."
fi

echo
echo ">>> Git status"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git status --short
    echo
    git diff --stat || true
fi

if command -v gitleaks >/dev/null 2>&1; then
    echo
    echo ">>> Secret scan"

    if gitleaks detect --no-banner; then
        echo "[PASS] Secret scan"
    else
        echo "[FAIL] Secret scan"
        FAILED=1
    fi
else
    echo
    echo "[INFO] Gitleaks not installed."
fi

echo
echo "============================================================"

if [[ "$FAILED" -eq 0 ]]; then
    echo "                 VERIFICATION PASSED"
    exit 0
else
    echo "                 VERIFICATION FAILED"
    exit 1
fi
EOF

chmod +x "$VERIFY"
ok "Created verify.sh"

else
    warn "Existing verify.sh preserved"
fi

# ------------------------------------------------------------
# Worktree helper
# ------------------------------------------------------------

WORKTREE="$PROJECT_DIR/new-worktree.sh"

if [[ ! -f "$WORKTREE" ]]; then

cat > "$WORKTREE" <<'EOF'
#!/usr/bin/env bash

set -euo pipefail

BRANCH="${1:-}"

if [[ -z "$BRANCH" ]]; then
    echo "Usage: ./new-worktree.sh feature-name"
    exit 1
fi

ROOT="$(git rev-parse --show-toplevel)"
PROJECT="$(basename "$ROOT")"
TARGET="../${PROJECT}-${BRANCH}"

git worktree add -b "$BRANCH" "$TARGET"

echo
echo "Worktree created:"
echo "$TARGET"
echo
echo "Run:"
echo "cd \"$TARGET\""
EOF

chmod +x "$WORKTREE"
ok "Created new-worktree.sh"

else
    warn "Existing new-worktree.sh preserved"
fi

# ------------------------------------------------------------
# Gitignore
# ------------------------------------------------------------

GITIGNORE="$PROJECT_DIR/.gitignore"
touch "$GITIGNORE"

for entry in \
    ".env" \
    ".env.*" \
    "*.pem" \
    "*.key" \
    "*.secret" \
    "node_modules/" \
    ".DS_Store"
do
    append_once "$GITIGNORE" "$entry"
done

ok ".gitignore protection configured"

# ------------------------------------------------------------
# Diagnostics
# ------------------------------------------------------------

echo
echo "============================================================"
echo "                    DIAGNOSTICS"
echo "============================================================"

echo
echo "OpenCode:"
opencode --version || true

echo
echo "MCP:"
opencode mcp list || true

echo
echo "Plugins:"
opencode plugin list || true

# ------------------------------------------------------------
# Complete
# ------------------------------------------------------------

echo
echo "============================================================"
echo "                 INSTALLATION COMPLETE"
echo "============================================================"
echo
echo "Restart your terminal or run:"
echo
echo "    source ~/.bashrc"
echo
echo "Then:"
echo
echo "    opencode --version"
echo "    opencode mcp list"
echo "    ./verify.sh"
echo
echo "For a separate feature:"
echo
echo "    ./new-worktree.sh feature-name"
echo
echo "Then launch:"
echo
echo "    opencode"
echo
echo "============================================================"
```

