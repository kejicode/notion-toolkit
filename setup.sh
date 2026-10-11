#!/bin/bash
# ============================================================================
#  Claude Code Keepalive - Interactive Setup
#  Usage: curl -fsSL <raw-url> | bash
#         or: git clone <repo> && cd <repo> && bash setup.sh
# ============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

INSTALL_DIR="$HOME/claude-keepalive"

info()    { echo -e "${CYAN}[*]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[✗]${NC} $*"; exit 1; }

banner() {
    echo -e "${BOLD}"
    cat << 'ART'
   _____ _                 _        _  __                    _ _
  / ____| |               | |      | |/ /                  | (_)
 | |    | | __ _ _   _  __| | ___  | ' / ___  ___ _ __   __| |___   _____
 | |    | |/ _` | | | |/ _` |/ _ \ |  < / _ \/ _ \ '_ \ / _` | \ \ / / _ \
 | |____| | (_| | |_| | (_| |  __/ | . \  __/  __/ |_) | (_| | |\ V /  __/
  \_____|_|\__,_|\__,_|\__,_|\___| |_|\_\___|\___| .__/ \__,_|_| \_/ \___|
                                                  | |
                                                  |_|
ART
    echo -e "${NC}"
    echo -e "${DIM}  Automated keepalive for Claude Code on VPS${NC}"
    echo ""
}

preflight() {
    info "Checking environment..."
    if ! command -v claude &>/dev/null; then
        warn "Claude Code CLI not found in PATH"
        echo -e "  Install: ${DIM}npm install -g @anthropic-ai/claude-code${NC}"
        read -rp "  Continue anyway? [y/N] " yn
        [[ "$yn" =~ ^[Yy]$ ]] || exit 0
    else
        success "Claude Code CLI found: $(which claude)"
    fi
    command -v git &>/dev/null || error "git is required but not installed"
    command -v crontab &>/dev/null || error "crontab is required but not installed"
    success "Environment checks passed"
    echo ""
}

collect_input() {
    echo -e "${BOLD}── Configuration ──${NC}"
    echo ""
    local default_label="acc-$(hostname -s | tr '[:upper:]' '[:lower:]')-$(date +%s | tail -c 5)"
    read -rp "$(echo -e "${CYAN}Account label${NC} [${DIM}${default_label}${NC}]: ")" ACCOUNT_LABEL
    ACCOUNT_LABEL="${ACCOUNT_LABEL:-$default_label}"
    echo ""
    echo -e "${DIM}  How to get your token:${NC}"
    echo -e "${DIM}  1. Run 'claude setup-token' in Termux or any CLI${NC}"
    echo -e "${DIM}  2. Login via the browser URL it gives you${NC}"
    echo -e "${DIM}  3. Copy the token and paste it below${NC}"
    echo ""
    while true; do
        read -rsp "$(echo -e "${CYAN}Setup Token${NC} (input hidden): ")" OAUTH_TOKEN
        echo ""
        if [ -z "$OAUTH_TOKEN" ]; then
            warn "Token cannot be empty, try again"
        else
            success "Token received (${#OAUTH_TOKEN} chars)"
            break
        fi
    done
    echo ""
    echo -e "  ${DIM}1) Every 2 hours (recommended)${NC}"
    echo -e "  ${DIM}2) Every 3 hours${NC}"
    echo -e "  ${DIM}3) Every 4 hours${NC}"
    echo -e "  ${DIM}4) Custom cron expression${NC}"
    read -rp "$(echo -e "${CYAN}Run interval${NC} [${DIM}1${NC}]: ")" interval_choice
    case "${interval_choice:-1}" in
        1) CRON_SCHEDULE="0 */2 * * *" ;;
        2) CRON_SCHEDULE="0 */3 * * *" ;;
        3) CRON_SCHEDULE="0 */4 * * *" ;;
        4) read -rp "  Cron expression: " CRON_SCHEDULE ;;
        *) CRON_SCHEDULE="0 */2 * * *" ;;
    esac
    read -rp "$(echo -e "${CYAN}Task timeout (sec)${NC} [${DIM}180${NC}]: ")" TASK_TIMEOUT
    TASK_TIMEOUT="${TASK_TIMEOUT:-180}"
    read -rp "$(echo -e "${CYAN}Log retention (days)${NC} [${DIM}7${NC}]: ")" LOG_RETAIN
    LOG_RETAIN="${LOG_RETAIN:-7}"
    echo ""
}

create_prompts() {
    local dir="$1"
    mkdir -p "$dir"
    echo "Review the project structure and suggest improvements to code organization." > "$dir/01.txt"
    echo "Check for potential performance issues or bottlenecks in the codebase." > "$dir/02.txt"
    echo "Summarize recent changes and list any remaining TODO items in the code." > "$dir/03.txt"
    echo "Analyze test coverage and suggest areas that need more testing." > "$dir/04.txt"
    echo "Review error handling patterns and suggest improvements for robustness." > "$dir/05.txt"
    echo "Look for any hardcoded values that should be moved to configuration." > "$dir/06.txt"
    echo "Check for code duplication and suggest refactoring opportunities." > "$dir/07.txt"
    echo "Review the README and documentation for accuracy and completeness." > "$dir/08.txt"
    echo "Analyze dependencies and check if any are outdated or have known issues." > "$dir/09.txt"
    echo "Suggest improvements to the project's logging and monitoring setup." > "$dir/10.txt"
}

create_keepalive_script() {
    cat > "$INSTALL_DIR/keepalive.sh" << 'KALIVE'
#!/bin/bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
source "$SCRIPT_DIR/config.env"
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/${ACCOUNT_LABEL}_$(date +%Y%m%d).log"
log() { echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$ACCOUNT_LABEL] $*" >> "$LOG_FILE"; }
log "========== Session Start =========="
PROMPT_FILE=$(find "$SCRIPT_DIR/prompts" -name '*.txt' -type f | shuf -n1)
PROMPT_CONTENT=$(cat "$PROMPT_FILE")
log "Prompt: $(basename "$PROMPT_FILE")"
JITTER=$((RANDOM % 300))
log "Jitter: ${JITTER}s"
sleep "$JITTER"
export CLAUDE_CODE_OAUTH_TOKEN
cd "$PROJECT_DIR"
if timeout "$TASK_TIMEOUT" claude -p "$PROMPT_CONTENT" >> "$LOG_FILE" 2>&1; then
    log "Completed successfully"
else
    EC=$?
    if [ $EC -eq 124 ]; then
        log "Timed out after ${TASK_TIMEOUT}s"
    else
        log "Failed with exit code: $EC"
    fi
fi
log "========== Session End ============"
find "$LOG_DIR" -name '*.log' -mtime +"$LOG_RETAIN_DAYS" -delete 2>/dev/null || true
KALIVE
    chmod +x "$INSTALL_DIR/keepalive.sh"
}

create_project_scaffold() {
    local proj_dir="$INSTALL_DIR/project"
    if [ -d "$proj_dir/.git" ]; then return; fi
    mkdir -p "$proj_dir"
    cd "$proj_dir"
    git init -q

    cat > main.py << 'PYEOF'
"""Data processing utilities for batch operations."""
import json
import logging
from pathlib import Path
from typing import Any
from datetime import datetime

logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)


class BatchProcessor:
    """Handles batch data transformation and validation."""

    def __init__(self, config_path: str = "config.json"):
        self.config = self._load_config(config_path)
        self.processed_count = 0
        self.error_count = 0

    def _load_config(self, path: str) -> dict:
        config_file = Path(path)
        if config_file.exists():
            with open(config_file) as f:
                return json.load(f)
        return {"batch_size": 100, "retry_attempts": 3, "output_dir": "output"}

    def validate(self, item: dict[str, Any]) -> bool:
        required = {'id', 'name', 'value', 'timestamp'}
        if not required.issubset(item.keys()):
            logger.warning(f"Missing keys in item {item.get('id', '?')}")
            return False
        return isinstance(item['value'], (int, float))

    def transform(self, item: dict[str, Any]) -> dict[str, Any]:
        return {**item, 'processed': True, 'value': round(item['value'] * 1.1, 2),
                'processed_at': datetime.now().isoformat()}

    def process_batch(self, items: list[dict]) -> list[dict]:
        results = []
        for item in items:
            if self.validate(item):
                results.append(self.transform(item))
                self.processed_count += 1
            else:
                self.error_count += 1
        return results

    def summary(self) -> dict:
        total = max(1, self.processed_count + self.error_count)
        return {"processed": self.processed_count, "errors": self.error_count,
                "success_rate": f"{self.processed_count / total * 100:.1f}%"}


def main():
    proc = BatchProcessor()
    data = [{"id": i, "name": f"item_{i}", "value": i * 10.5,
             "timestamp": datetime.now().isoformat()} for i in range(1, 51)]
    results = proc.process_batch(data)
    logger.info(f"Batch complete: {json.dumps(proc.summary())}")
    out = Path(proc.config["output_dir"])
    out.mkdir(exist_ok=True)
    with open(out / "results.json", "w") as f:
        json.dump(results, f, indent=2)


if __name__ == '__main__':
    main()
PYEOF

    cat > utils.py << 'UTILEOF'
"""Shared utility functions."""
import hashlib
import re
from functools import lru_cache


@lru_cache(maxsize=256)
def slugify(text: str) -> str:
    text = text.lower().strip()
    text = re.sub(r'[^\w\s-]', '', text)
    return re.sub(r'[-\s]+', '-', text)


def checksum(data: str) -> str:
    return hashlib.sha256(data.encode()).hexdigest()[:12]


def chunk_list(lst: list, size: int) -> list[list]:
    return [lst[i:i + size] for i in range(0, len(lst), size)]
UTILEOF

    echo '{"batch_size":100,"retry_attempts":3,"output_dir":"output","log_level":"INFO"}' > config.json
    echo -e "python-dotenv>=1.0.0\npydantic>=2.0.0" > requirements.txt

    cat > README.md << 'MDEOF'
# Data Processing Utils
Lightweight batch data processing utilities.

## Usage
```bash
python main.py
```
MDEOF

    echo -e "__pycache__/\n*.pyc\noutput/\n.env\n*.log" > .gitignore
    git add -A && git commit -q -m "Initial commit: batch processing utilities"
    cd - > /dev/null
}

create_structure() {
    info "Creating file structure..."
    mkdir -p "$INSTALL_DIR/logs"

    # Config
    cat > "$INSTALL_DIR/config.env" << ENVEOF
ACCOUNT_LABEL="${ACCOUNT_LABEL}"
CLAUDE_CODE_OAUTH_TOKEN="${OAUTH_TOKEN}"
PROJECT_DIR="${INSTALL_DIR}/project"
CRON_SCHEDULE="${CRON_SCHEDULE}"
TASK_TIMEOUT=${TASK_TIMEOUT}
LOG_RETAIN_DAYS=${LOG_RETAIN}
ENVEOF
    chmod 600 "$INSTALL_DIR/config.env"
    success "Config written (permissions: 600)"

    create_prompts "$INSTALL_DIR/prompts"
    success "Prompt pool created (10 prompts)"

    create_keepalive_script
    success "Keepalive script created"

    create_project_scaffold
    success "Project scaffold initialized"
}

install_cron() {
    info "Installing cron job..."
    local cron_line="$CRON_SCHEDULE /bin/bash $INSTALL_DIR/keepalive.sh"
    (crontab -l 2>/dev/null | grep -v "claude-keepalive/keepalive.sh" || true; echo "$cron_line") | crontab -
    success "Cron installed: $CRON_SCHEDULE"
}

show_summary() {
    echo ""
    echo -e "${BOLD}── Installation Summary ──${NC}"
    echo ""
    echo -e "  Account:     ${GREEN}${ACCOUNT_LABEL}${NC}"
    echo -e "  Install dir: ${DIM}${INSTALL_DIR}${NC}"
    echo -e "  Schedule:    ${CRON_SCHEDULE}"
    echo -e "  Timeout:     ${TASK_TIMEOUT}s"
    echo -e "  Log retain:  ${LOG_RETAIN} days"
    echo -e "  Prompts:     $(find "$INSTALL_DIR/prompts" -name '*.txt' | wc -l) in pool"
    echo ""
    echo -e "  ${DIM}Cron entry:${NC}"
    echo -e "  $(crontab -l 2>/dev/null | grep keepalive)"
    echo ""
    echo -e "${BOLD}── Commands ──${NC}"
    echo ""
    echo -e "  Test run:       ${DIM}bash ~/claude-keepalive/keepalive.sh${NC}"
    echo -e "  View logs:      ${DIM}tail -f ~/claude-keepalive/logs/*.log${NC}"
    echo -e "  Update token:   ${DIM}bash $0 --update-token${NC}"
    echo -e "  Check status:   ${DIM}bash $0 --status${NC}"
    echo -e "  Uninstall:      ${DIM}bash $0 --uninstall${NC}"
    echo ""
}

update_token() {
    [ -f "$INSTALL_DIR/config.env" ] || error "No installation found at $INSTALL_DIR"
    echo -e "${BOLD}── Update Token ──${NC}"
    source "$INSTALL_DIR/config.env"
    echo -e "  Account: ${GREEN}${ACCOUNT_LABEL}${NC}"
    echo ""
    read -rsp "$(echo -e "${CYAN}New token${NC} (hidden): ")" new_token
    echo ""
    [ -z "$new_token" ] && error "Token cannot be empty"
    sed -i "s|^CLAUDE_CODE_OAUTH_TOKEN=.*|CLAUDE_CODE_OAUTH_TOKEN=\"${new_token}\"|" "$INSTALL_DIR/config.env"
    success "Token updated (${#new_token} chars)"
}

show_status() {
    [ -f "$INSTALL_DIR/config.env" ] || error "No installation found at $INSTALL_DIR"
    source "$INSTALL_DIR/config.env"
    echo -e "${BOLD}── Status: ${ACCOUNT_LABEL} ──${NC}"
    echo ""
    if crontab -l 2>/dev/null | grep -q "keepalive.sh"; then
        success "Cron active"
        echo -e "  $(crontab -l 2>/dev/null | grep keepalive)"
    else
        warn "Cron not found"
    fi
    echo ""
    local latest=$(ls -t "$INSTALL_DIR/logs/"*.log 2>/dev/null | head -1)
    if [ -n "$latest" ]; then
        echo -e "  ${DIM}Latest: $latest${NC}"
        tail -3 "$latest" | sed 's/^/    /'
    else
        warn "No logs yet"
    fi
    echo ""
    local tlen=${#CLAUDE_CODE_OAUTH_TOKEN}
    if [ "$tlen" -gt 10 ]; then
        success "Token configured (${tlen} chars)"
    else
        warn "Token looks short (${tlen} chars)"
    fi
}

do_uninstall() {
    echo -e "${BOLD}── Uninstall ──${NC}"
    echo ""
    warn "Will remove: $INSTALL_DIR + cron job"
    read -rp "$(echo -e "${RED}Confirm?${NC} [y/N] ")" yn
    [[ "$yn" =~ ^[Yy]$ ]] || { info "Cancelled."; exit 0; }
    (crontab -l 2>/dev/null | grep -v "claude-keepalive/keepalive.sh" || true) | crontab -
    rm -rf "$INSTALL_DIR"
    success "Fully uninstalled"
}

main() {
    case "${1:-}" in
        --update-token) update_token; exit 0 ;;
        --status)       show_status;  exit 0 ;;
        --uninstall)    do_uninstall; exit 0 ;;
        --help|-h)      echo "Usage: $0 [--update-token|--status|--uninstall|--help]"; exit 0 ;;
    esac
    banner
    preflight
    collect_input
    create_structure
    install_cron
    show_summary

    read -rp "$(echo -e "${CYAN}Run a test now?${NC} [Y/n] ")" rt
    if [[ ! "$rt" =~ ^[Nn]$ ]]; then
        info "Running test..."
        bash "$INSTALL_DIR/keepalive.sh" && success "Test done! Check logs." || warn "Test had warnings, check logs."
    fi
    echo ""
    success "All set! Keepalive is running on schedule."
    echo ""
}

main "$@"
