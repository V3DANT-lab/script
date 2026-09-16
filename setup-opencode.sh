#!/usr/bin/env bash

set -Eeuo pipefail

# ============================================================
# OpenCode Power Setup
# ============================================================

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
BACKUP_DIR="$CONFIG_DIR/backups"
PROJECT_DIR="$(pwd)"

info() {
    printf '\n[INFO] %s\n' "$*"
}

ok() {
    printf '[ OK ] %s\n' "$*"
}

warn() {
    printf '[WARN] %s\n' "$*"
}

error() {
    printf '[ERROR] %s\n' "$*" >&2
}

backup_file() {
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

    if ! grep -Fqx "$value" "$file" 2>/dev/null; then
        printf '%s\n' "$value" >> "$file"
    fi
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# ============================================================
# Header
# ============================================================

clear 2>/dev/null || true

echo "============================================================"
echo "             OPENCODE POWER SETUP"
echo "============================================================"
echo
echo "This setup configures:"
echo
echo "  • OpenCode"
echo "  • OpenCode Mem"
echo "  • Dynamic Context Pruning"
echo "  • EnvSitter Guard"
echo "  • Oh My OpenCode Slim"
echo "  • Background subagents"
echo "  • Exa web search"
echo "  • OpenCode notifications"
echo "  • Obot MCP"
echo "  • AGENTS.md"
echo "  • Verification pipeline"
echo "  • Git worktree helper"
echo
echo "Existing configuration will be backed up."
echo "============================================================"

# ============================================================
# Dependency checks
# ============================================================

info "Checking required dependencies..."

for command in curl git node npm; do
    if ! command_exists "$command"; then
        error "Missing dependency: $command"
        echo
        echo "Please install $command and run this script again."
        exit 1
    fi
done

NODE_MAJOR="$(
    node -v |
    sed 's/^v//' |
    cut -d. -f1
)"

if (( NODE_MAJOR < 20 )); then
    error "Node.js 20 or newer is required."
    echo "Detected: $(node -v)"
    exit 1
fi

ok "Node.js $(node -v)"
ok "npm $(npm --version)"
ok "git available"
ok "curl available"

# ============================================================
# Install / update OpenCode
# ============================================================

info "Installing/updating OpenCode..."

if npm install -g @opencode/cli@latest; then
    ok "OpenCode package installed"
else
    error "OpenCode installation failed."
    exit 1
fi

# npm may update PATH only after the shell refreshes.
export PATH="$(npm prefix -g)/bin:$PATH"

if ! command_exists opencode; then
    error "OpenCode command was not found after installation."
    echo
    echo "Try:"
    echo "  export PATH=\"$(npm prefix -g)/bin:\$PATH\""
    echo "  opencode --version"
    exit 1
fi

OPENCODE_VERSION="$(opencode --version 2>/dev/null || true)"

if [[ -n "$OPENCODE_VERSION" ]]; then
    ok "OpenCode $OPENCODE_VERSION"
else
    warn "OpenCode installed, but version could not be detected."
fi

# ============================================================
# OpenCode directories
# ============================================================

info "Preparing OpenCode directories..."

mkdir -p \
    "$CONFIG_DIR" \
    "$CONFIG_DIR/backups" \
    "$CONFIG_DIR/agents" \
    "$CONFIG_DIR/commands" \
    "$CONFIG_DIR/skills" \
    "$CONFIG_DIR/plugins"

backup_file "$CONFIG_DIR/opencode.json"
backup_file "$CONFIG_DIR/opencode.jsonc"

ok "OpenCode directories ready"

# ============================================================
# OpenCode plugins
# ============================================================

info "Installing OpenCode plugins..."

install_plugin() {
    local plugin="$1"

    info "Installing $plugin..."

    if opencode plugin add --global "$plugin"; then
        ok "Installed $plugin"
    else
        warn "Could not install $plugin automatically."
        echo "You can install it later with:"
        echo "  opencode plugin add --global \"$plugin\""
    fi
}

# Persistent memory
install_plugin "opencode-mem"

# Dynamic Context Pruning
install_plugin "@chikage0o0/opencode-dcp"

# Secret/environment protection
install_plugin "envsitter-guard@latest"

# ============================================================
# Oh My OpenCode Slim
# ============================================================

info "Installing Oh My OpenCode Slim..."

if command_exists bunx; then

    if bunx oh-my-opencode-slim@latest install \
        --no-tui \
        --skills=yes \
        --background-subagents=yes; then

        ok "Oh My OpenCode Slim configured"

    else
        warn "Oh My OpenCode Slim installation failed."
    fi

else

    if npx oh-my-opencode-slim@latest install \
        --no-tui \
        --skills=yes \
        --background-subagents=yes; then

        ok "Oh My OpenCode Slim configured"

    else
        warn "Oh My OpenCode Slim installation failed."
    fi

fi

# ============================================================
# Shell environment
# ============================================================

info "Configuring background-agent environment..."

if [[ "${SHELL:-}" == */zsh ]]; then
    SHELL_RC="$HOME/.zshrc"
else
    SHELL_RC="$HOME/.bashrc"
fi

append_once \
    "$SHELL_RC" \
    'export OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS=true'

append_once \
    "$SHELL_RC" \
    'export OPENCODE_ENABLE_EXA=1'

# Also activate them immediately for this shell.
export OPENCODE_EXPERIMENTAL_BACKGROUND_SUBAGENTS=true
export OPENCODE_ENABLE_EXA=1

ok "Background subagents enabled"
ok "Exa web search environment configured"

# ============================================================
# Obot MCP
# ============================================================

echo
echo "============================================================"
echo "                 OBOT MCP CONFIGURATION"
echo "============================================================"
echo
echo "Obot is optional."
echo "If you have an Obot MCP endpoint, enter it below."
echo "Leave it empty to skip this step."
echo

read -r -p "Obot MCP URL: " OBOT_URL

if [[ -n "${OBOT_URL:-}" ]]; then

    if opencode mcp add obot --global --url "$OBOT_URL"; then
        ok "Obot MCP registered"
    else
        warn "Obot MCP could not be registered."
        echo
        echo "You can retry later with:"
        echo
        echo "  opencode mcp add obot --global --url \"$OBOT_URL\""
    fi

else
    warn "Obot skipped."
fi

# ============================================================
# AGENTS.md
# ============================================================

AGENTS="$PROJECT_DIR/AGENTS.md"

if [[ ! -f "$AGENTS" ]]; then

cat > "$AGENTS" <<'EOF'
# AGENTS.md

## Development Workflow

For substantial tasks use this verification loop:

1. Inspect the repository.
2. Understand the existing architecture.
3. Plan the change.
4. Implement the smallest appropriate change.
5. Run linting.
6. Run type checking.
7. Run tests.
8. Build the project.
9. Run the application when possible.
10. Perform runtime verification.
11. Inspect failures.
12. Fix failures.
13. Repeat verification.

Do not declare a task complete merely because the code compiles.

## Existing Architecture

Before changing code:

- inspect existing files
- inspect package.json
- inspect configuration
- inspect database schema
- inspect existing APIs
- inspect existing components
- reuse existing architecture where practical

Avoid unnecessary rewrites.

## Dependencies

Do not add a dependency unless it is actually required.

Before adding one:

- check whether an existing dependency already provides the functionality
- check compatibility with the project
- understand its purpose

## Security

Never commit:

- .env
- .env.*
- API keys
- access tokens
- passwords
- private keys
- credentials
- certificates containing secrets

Use environment variables or the appropriate secret-management mechanism.

## Database

Before changing database code:

1. Inspect the schema.
2. Inspect migrations.
3. Inspect relationships.
4. Inspect existing queries.
5. Check affected frontend/backend code.
6. Test affected database operations.

Never destroy existing data unless explicitly instructed.

## Git

Before committing:

- run git status
- inspect the diff
- inspect changed files
- check for secrets
- verify tests/build status

## Worktrees

For large or risky changes, prefer a Git worktree.

## Completion Report

Before declaring completion, report:

- what changed
- files changed
- tests performed
- lint/typecheck/build status
- runtime verification
- remaining issues
EOF

    ok "Created AGENTS.md"

else
    warn "Existing AGENTS.md preserved"
fi

# ============================================================
# Verification script
# ============================================================

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
echo "                PROJECT VERIFICATION"
echo "============================================================"

# ------------------------------------------------------------
# OpenCode
# ------------------------------------------------------------

if command -v opencode >/dev/null 2>&1; then
    run_check "OpenCode version" opencode --version
else
    echo "[FAIL] OpenCode is not available"
    FAILED=1
fi

# ------------------------------------------------------------
# Project scripts
# ------------------------------------------------------------

if [[ -f package.json ]]; then

    echo
    echo ">>> package.json scripts"

    npm run 2>/dev/null || true

    if npm run 2>/dev/null |
        grep -qE '(^|[[:space:]])lint($|[[:space:]])'; then

        run_check "Lint" npm run lint
    fi

    if npm run 2>/dev/null |
        grep -qE '(^|[[:space:]])typecheck($|[[:space:]])'; then

        run_check "Typecheck" npm run typecheck
    fi

    if npm run 2>/dev/null |
        grep -qE '(^|[[:space:]])test($|[[:space:]])'; then

        run_check "Tests" npm test
    fi

    if npm run 2>/dev/null |
        grep -qE '(^|[[:space:]])build($|[[:space:]])'; then

        run_check "Build" npm run build
    fi

else

    echo
    echo "[INFO] package.json not found."

fi

# ------------------------------------------------------------
# Git
# ------------------------------------------------------------

echo
echo ">>> Git status"

if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then

    git status --short

    echo
    git diff --stat || true

else

    echo "[INFO] Not inside a Git repository."

fi

# ------------------------------------------------------------
# Secret scan
# ------------------------------------------------------------

echo
echo ">>> Secret scanning"

if command -v gitleaks >/dev/null 2>&1; then

    if gitleaks detect --no-banner; then
        echo "[PASS] Gitleaks"
    else
        echo "[FAIL] Gitleaks detected possible secrets"
        FAILED=1
    fi

else

    echo "[INFO] Gitleaks is not installed."
    echo "[INFO] Secret scan skipped."

fi

# ------------------------------------------------------------
# Result
# ------------------------------------------------------------

echo
echo "============================================================"

if [[ "$FAILED" -eq 0 ]]; then

    echo "             VERIFICATION PASSED"

    exit 0

else

    echo "             VERIFICATION FAILED"

    exit 1

fi
EOF

chmod +x "$VERIFY"

ok "Created verify.sh"

else

    warn "Existing verify.sh preserved"

fi

# ============================================================
# Git worktree helper
# ============================================================

WORKTREE="$PROJECT_DIR/new-worktree.sh"

if [[ ! -f "$WORKTREE" ]]; then

cat > "$WORKTREE" <<'EOF'
#!/usr/bin/env bash

set -Eeuo pipefail

BRANCH="${1:-}"

if [[ -z "$BRANCH" ]]; then
    echo "Usage:"
    echo
    echo "  ./new-worktree.sh feature-name"
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

# ============================================================
# Gitignore
# ============================================================

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

# ============================================================
# Diagnostics
# ============================================================

echo
echo "============================================================"
echo "                    DIAGNOSTICS"
echo "============================================================"

echo
echo "OpenCode:"
opencode --version || true

echo
echo "OpenCode configuration path:"
opencode debug paths config || true

echo
echo "MCP servers:"
opencode mcp list || true

echo
echo "Plugins:"
opencode plugin list || true

# ============================================================
# Completion
# ============================================================

echo
echo "============================================================"
echo "                 SETUP FINISHED"
echo "============================================================"

echo
echo "Reload your shell:"
echo
echo "  source ~/.bashrc"
echo
echo "Then verify:"
echo
echo "  opencode --version"
echo "  opencode plugin list"
echo "  opencode mcp list"
echo "  ./verify.sh"
echo
echo "Launch OpenCode:"
echo
echo "  opencode"
echo
echo "============================================================"