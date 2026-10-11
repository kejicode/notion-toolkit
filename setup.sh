#!/bin/bash
# ============================================================================
#  Notion Toolkit - Development Environment Setup
#  Usage: bash <(curl -fsSL https://raw.githubusercontent.com/kejicode/notion-toolkit/main/setup.sh)
# ============================================================================
set -euo pipefail

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'

INSTALL_DIR="$HOME/notion-toolkit"

info()    { echo -e "${CYAN}[*]${NC} $*"; }
success() { echo -e "${GREEN}[✓]${NC} $*"; }
warn()    { echo -e "${YELLOW}[!]${NC} $*"; }
error()   { echo -e "${RED}[✗]${NC} $*"; exit 1; }

banner() {
    echo -e "${BOLD}"
    cat << 'ART'
  _   _       _   _               _____           _ _    _ _
 | \ | |     | | (_)             |_   _|         | | |  (_) |
 |  \| | ___ | |_ _  ___  _ __    | |  ___   ___ | | | ___| |_
 | . ` |/ _ \| __| |/ _ \| '_ \   | | / _ \ / _ \| | |/ / | __|
 | |\  | (_) | |_| | (_) | | | |  | || (_) | (_) | |   <| | |_
 |_| \_|\___/ \__|_|\___/|_| |_|  \_/ \___/ \___/|_|_|\_\_|\__|
ART
    echo -e "${NC}"
    echo -e "${DIM}  Notion API toolkit - local development environment setup${NC}"
    echo ""
}

install_deps() {
    info "Checking dependencies..."

    # nodejs + npm
    if ! command -v node &>/dev/null || ! command -v npm &>/dev/null; then
        warn "Node.js / npm not found, installing..."
        if command -v apt &>/dev/null; then
            sudo apt update -qq && sudo apt install -y nodejs npm
        else
            error "Unsupported package manager. Please install nodejs and npm manually."
        fi
        success "Node.js $(node -v) / npm $(npm -v) installed"
    else
        success "Node.js $(node -v) / npm $(npm -v) found"
    fi

    # claude code CLI
    if ! command -v claude &>/dev/null; then
        warn "CLI not found, installing..."
        sudo npm install -g @anthropic-ai/claude-code
        if command -v claude &>/dev/null; then
            success "CLI installed: $(which claude)"
        else
            error "CLI installation failed"
        fi
    else
        success "CLI found: $(which claude)"
    fi

    # git
    if ! command -v git &>/dev/null; then
        warn "git not found, installing..."
        sudo apt install -y git
    fi
    success "git found"

    # crontab
    if ! command -v crontab &>/dev/null; then
        warn "cron not found, installing..."
        sudo apt install -y cron
        sudo systemctl enable cron && sudo systemctl start cron
    fi
    success "cron found"

    echo ""
}

collect_input() {
    echo -e "${BOLD}── Configuration ──${NC}"
    echo ""
    local default_label="acc-$(hostname -s | tr '[:upper:]' '[:lower:]')-$(date +%s | tail -c 5)"
    read -rp "$(echo -e "${CYAN}Account label${NC} [${DIM}${default_label}${NC}]: ")" ACCOUNT_LABEL
    ACCOUNT_LABEL="${ACCOUNT_LABEL:-$default_label}"
    echo ""
    echo -e "  ${DIM}1) Auto - generate auth link on this machine (recommended)${NC}"
    echo -e "  ${DIM}2) Manual - paste a token you already have${NC}"
    read -rp "$(echo -e "${CYAN}Auth method${NC} [${DIM}1${NC}]: ")" auth_method
    echo ""

    if [[ "${auth_method:-1}" == "2" ]]; then
        # Manual token input
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
    else
        # Auto: run claude setup-token and capture output
        info "Generating auth link..."
        echo ""

        TOKEN_OUTPUT=$(claude setup-token 2>&1) || true

        # Extract the URL for the user
        AUTH_URL=$(echo "$TOKEN_OUTPUT" | grep -oP 'https://[^\s]+' | head -1)
        if [ -n "$AUTH_URL" ]; then
            echo -e "  ${BOLD}Open this link in your browser to authorize:${NC}"
            echo ""
            echo -e "  ${CYAN}${AUTH_URL}${NC}"
            echo ""
        fi

        # Extract the token from output
        OAUTH_TOKEN=$(echo "$TOKEN_OUTPUT" | grep -oP '(?<=token:\s).*' | head -1)

        # If auto-extraction failed, ask user to paste it
        if [ -z "$OAUTH_TOKEN" ]; then
            echo -e "${DIM}  After authorizing, copy the token shown and paste it below${NC}"
            echo ""
            while true; do
                read -rsp "$(echo -e "${CYAN}Setup Token${NC} (input hidden): ")" OAUTH_TOKEN
                echo ""
                if [ -z "$OAUTH_TOKEN" ]; then
                    warn "Token cannot be empty, try again"
                else
                    break
                fi
            done
        fi
        success "Token received (${#OAUTH_TOKEN} chars)"
    fi
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
    echo "Add proper retry logic with exponential backoff to the NotionClient API calls in client.py. Currently failures just raise immediately." > "$dir/01.txt"
    echo "Implement the CSV export feature in exporter.py - the export_csv method is still a stub. It should handle all Notion property types properly." > "$dir/02.txt"
    echo "Add input validation to the CLI commands in cli.py. Right now there's no validation on database IDs or page IDs before making API calls." > "$dir/03.txt"
    echo "Write unit tests for the NotionClient class in client.py. Focus on testing error handling, pagination, and the query builder." > "$dir/04.txt"
    echo "Refactor the property type handling in exporter.py - the _format_property method has too many if/elif branches. Consider using a dispatch dict or strategy pattern." > "$dir/05.txt"
    echo "Add a markdown export feature to exporter.py. It should convert Notion page content blocks into clean markdown with proper heading levels, lists, and code blocks." > "$dir/06.txt"
    echo "Review the config.py module and add support for multiple workspace configurations. Currently it only handles a single API key." > "$dir/07.txt"
    echo "Add proper logging throughout the project. Most modules use print statements instead of the logging module. Add appropriate log levels." > "$dir/08.txt"
    echo "Implement the search command in cli.py - it currently just prints 'not implemented'. It should search across pages and databases by title." > "$dir/09.txt"
    echo "Add rate limiting to the NotionClient to respect Notion's API rate limits (3 requests per second). The current implementation has no throttling." > "$dir/10.txt"
    echo "Fix the pagination bug in client.py query_database - when has_more is true it doesn't pass the start_cursor correctly to the next request." > "$dir/11.txt"
    echo "Add type hints to all functions in utils.py and exporter.py. Several functions are missing return type annotations." > "$dir/12.txt"
    echo "Implement a cache layer for frequently accessed pages. Add a simple TTL-based cache in client.py to avoid redundant API calls." > "$dir/13.txt"
    echo "Add a 'sync' command to cli.py that watches a Notion database and automatically exports changes to local files on an interval." > "$dir/14.txt"
    echo "Write integration tests that verify the full export pipeline: query database -> format properties -> write CSV/JSON output files." > "$dir/15.txt"
    echo "Review and improve error messages throughout the project. Many exceptions just say 'API error' without including the status code or Notion's error message." > "$dir/16.txt"
    echo "Add a --filter flag to the export CLI command so users can filter database rows by property values before exporting." > "$dir/17.txt"
    echo "Refactor config.py to use pydantic for settings validation instead of raw dict access. Add proper defaults and type checking." > "$dir/18.txt"
}

create_runner_script() {
    cat > "$INSTALL_DIR/runner.sh" << 'KALIVE'
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
if timeout "$TASK_TIMEOUT" claude -p "$PROMPT_CONTENT" --model "$CLAUDE_MODEL" --effort "$CLAUDE_EFFORT" >> "$LOG_FILE" 2>&1; then
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
    chmod +x "$INSTALL_DIR/runner.sh"
}

create_project_scaffold() {
    local proj_dir="$INSTALL_DIR/project"
    if [ -d "$proj_dir/.git" ]; then return; fi
    mkdir -p "$proj_dir/notion_toolkit" "$proj_dir/tests"
    cd "$proj_dir"
    git init -q

    # --- notion_toolkit/__init__.py ---
    cat > notion_toolkit/__init__.py << 'PYEOF'
"""Notion Toolkit - CLI tools for Notion API."""
__version__ = "0.3.1"
PYEOF

    # --- notion_toolkit/client.py ---
    cat > notion_toolkit/client.py << 'PYEOF'
"""Notion API client wrapper."""
import requests
import time
from typing import Any, Optional


NOTION_API_BASE = "https://api.notion.com/v1"
NOTION_VERSION = "2022-06-28"


class NotionClient:
    """Wrapper around the Notion API with pagination support."""

    def __init__(self, api_key: str, timeout: int = 30):
        self.api_key = api_key
        self.timeout = timeout
        self.session = requests.Session()
        self.session.headers.update({
            "Authorization": f"Bearer {api_key}",
            "Notion-Version": NOTION_VERSION,
            "Content-Type": "application/json",
        })
        self._request_count = 0

    def _request(self, method: str, endpoint: str, **kwargs) -> dict:
        """Make an API request. TODO: add retry logic with backoff."""
        url = f"{NOTION_API_BASE}/{endpoint}"
        self._request_count += 1
        resp = self.session.request(method, url, timeout=self.timeout, **kwargs)
        if resp.status_code == 429:
            # Rate limited - just raise for now
            # TODO: implement proper rate limiting
            raise Exception("API error: rate limited")
        if not resp.ok:
            raise Exception(f"API error: {resp.status_code}")
        return resp.json()

    def get_page(self, page_id: str) -> dict:
        """Retrieve a page by ID."""
        return self._request("GET", f"pages/{page_id}")

    def get_page_content(self, page_id: str) -> list[dict]:
        """Get all blocks (content) of a page."""
        blocks = []
        has_more = True
        cursor = None
        while has_more:
            params = {"page_size": 100}
            if cursor:
                params["start_cursor"] = cursor
            data = self._request("GET", f"blocks/{page_id}/children", params=params)
            blocks.extend(data.get("results", []))
            has_more = data.get("has_more", False)
            cursor = data.get("next_cursor")
        return blocks

    def query_database(self, database_id: str, filter_obj: Optional[dict] = None,
                       sorts: Optional[list] = None, page_size: int = 100) -> list[dict]:
        """Query a database with optional filters and sorting."""
        all_results = []
        has_more = True
        start_cursor = None
        while has_more:
            body: dict[str, Any] = {"page_size": page_size}
            if filter_obj:
                body["filter"] = filter_obj
            if sorts:
                body["sorts"] = sorts
            if start_cursor:
                body["start_cursor"] = start_cursor
            data = self._request("POST", f"databases/{database_id}/query", json=body)
            all_results.extend(data.get("results", []))
            has_more = data.get("has_more", False)
            # BUG: should use data.get("next_cursor") but sometimes doesn't update
            start_cursor = data.get("next_cursor")
        return all_results

    def search(self, query: str, filter_type: Optional[str] = None) -> list[dict]:
        """Search across all pages and databases.
        filter_type can be 'page' or 'database'.
        """
        body: dict[str, Any] = {"query": query}
        if filter_type:
            body["filter"] = {"value": filter_type, "property": "object"}
        data = self._request("POST", "search", json=body)
        return data.get("results", [])

    def get_database(self, database_id: str) -> dict:
        """Retrieve database metadata including schema."""
        return self._request("GET", f"databases/{database_id}")
PYEOF

    # --- notion_toolkit/exporter.py ---
    cat > notion_toolkit/exporter.py << 'PYEOF'
"""Export Notion data to various formats."""
import csv
import json
from pathlib import Path
from typing import Any
from datetime import datetime


class NotionExporter:
    """Export Notion database contents to files."""

    def __init__(self, output_dir: str = "output"):
        self.output_dir = Path(output_dir)
        self.output_dir.mkdir(parents=True, exist_ok=True)

    def _format_property(self, prop: dict) -> str:
        """Convert a Notion property value to a plain string."""
        prop_type = prop.get("type", "")

        if prop_type == "title":
            parts = prop.get("title", [])
            return "".join(p.get("plain_text", "") for p in parts)
        elif prop_type == "rich_text":
            parts = prop.get("rich_text", [])
            return "".join(p.get("plain_text", "") for p in parts)
        elif prop_type == "number":
            val = prop.get("number")
            return str(val) if val is not None else ""
        elif prop_type == "select":
            sel = prop.get("select")
            return sel.get("name", "") if sel else ""
        elif prop_type == "multi_select":
            items = prop.get("multi_select", [])
            return ", ".join(i.get("name", "") for i in items)
        elif prop_type == "date":
            date_obj = prop.get("date")
            if not date_obj:
                return ""
            start = date_obj.get("start", "")
            end = date_obj.get("end", "")
            return f"{start} → {end}" if end else start
        elif prop_type == "checkbox":
            return str(prop.get("checkbox", False))
        elif prop_type == "url":
            return prop.get("url", "") or ""
        elif prop_type == "email":
            return prop.get("email", "") or ""
        elif prop_type == "phone_number":
            return prop.get("phone_number", "") or ""
        elif prop_type == "status":
            status = prop.get("status")
            return status.get("name", "") if status else ""
        elif prop_type == "people":
            people = prop.get("people", [])
            return ", ".join(p.get("name", "Unknown") for p in people)
        elif prop_type == "relation":
            relations = prop.get("relation", [])
            return ", ".join(r.get("id", "") for r in relations)
        elif prop_type == "formula":
            formula = prop.get("formula", {})
            f_type = formula.get("type", "")
            return str(formula.get(f_type, ""))
        # TODO: handle rollup, created_time, last_edited_time, files
        else:
            return f"[{prop_type}]"

    def export_json(self, rows: list[dict], filename: str = "export.json") -> Path:
        """Export database rows to JSON."""
        output = []
        for row in rows:
            props = row.get("properties", {})
            item = {"id": row.get("id", ""), "url": row.get("url", "")}
            for name, prop in props.items():
                item[name] = self._format_property(prop)
            output.append(item)

        filepath = self.output_dir / filename
        with open(filepath, "w", encoding="utf-8") as f:
            json.dump(output, f, indent=2, ensure_ascii=False)
        return filepath

    def export_csv(self, rows: list[dict], filename: str = "export.csv") -> Path:
        """Export database rows to CSV.
        TODO: implement this properly
        """
        if not rows:
            filepath = self.output_dir / filename
            filepath.touch()
            return filepath

        # Get all property names from first row as headers
        first_props = rows[0].get("properties", {})
        headers = ["id"] + list(first_props.keys())

        filepath = self.output_dir / filename
        with open(filepath, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f)
            writer.writerow(headers)
            for row in rows:
                props = row.get("properties", {})
                csv_row = [row.get("id", "")]
                for h in headers[1:]:
                    prop = props.get(h, {})
                    csv_row.append(self._format_property(prop))
                writer.writerow(csv_row)
        return filepath

    def export_markdown(self, blocks: list[dict], filename: str = "page.md") -> Path:
        """Export page content blocks to Markdown.
        TODO: implement block-to-markdown conversion
        """
        # Stub - needs implementation
        filepath = self.output_dir / filename
        lines = []
        for block in blocks:
            block_type = block.get("type", "")
            # Very basic conversion - needs much more work
            if block_type == "paragraph":
                texts = block.get("paragraph", {}).get("rich_text", [])
                line = "".join(t.get("plain_text", "") for t in texts)
                lines.append(line)
            elif block_type.startswith("heading_"):
                level = int(block_type[-1])
                texts = block.get(block_type, {}).get("rich_text", [])
                line = "".join(t.get("plain_text", "") for t in texts)
                lines.append(f"{'#' * level} {line}")
            else:
                lines.append(f"<!-- unsupported: {block_type} -->")
        filepath.write_text("\n\n".join(lines), encoding="utf-8")
        return filepath
PYEOF

    # --- notion_toolkit/config.py ---
    cat > notion_toolkit/config.py << 'PYEOF'
"""Configuration management."""
import json
import os
from pathlib import Path


DEFAULT_CONFIG_PATH = Path.home() / ".notion-toolkit" / "config.json"

# Hardcoded defaults - should probably use a proper config class
DEFAULT_OUTPUT_DIR = "output"
DEFAULT_TIMEOUT = 30
DEFAULT_PAGE_SIZE = 100


def load_config(path: str = None) -> dict:
    """Load config from file or environment."""
    config = {
        "api_key": None,
        "output_dir": DEFAULT_OUTPUT_DIR,
        "timeout": DEFAULT_TIMEOUT,
        "page_size": DEFAULT_PAGE_SIZE,
    }

    # Try config file
    config_path = Path(path) if path else DEFAULT_CONFIG_PATH
    if config_path.exists():
        with open(config_path) as f:
            file_config = json.load(f)
            config.update(file_config)

    # Environment overrides
    env_key = os.environ.get("NOTION_API_KEY")
    if env_key:
        config["api_key"] = env_key

    # TODO: add support for multiple workspace configs
    # TODO: validate config values with pydantic

    return config


def save_config(config: dict, path: str = None):
    """Save config to file."""
    config_path = Path(path) if path else DEFAULT_CONFIG_PATH
    config_path.parent.mkdir(parents=True, exist_ok=True)
    with open(config_path, "w") as f:
        json.dump(config, f, indent=2)
    print(f"Config saved to {config_path}")


def init_config():
    """Interactive config initialization."""
    print("Notion Toolkit Setup")
    print("=" * 40)
    api_key = input("Notion API Key (from integrations page): ").strip()
    output_dir = input(f"Output directory [{DEFAULT_OUTPUT_DIR}]: ").strip() or DEFAULT_OUTPUT_DIR

    config = {
        "api_key": api_key,
        "output_dir": output_dir,
        "timeout": DEFAULT_TIMEOUT,
        "page_size": DEFAULT_PAGE_SIZE,
    }
    save_config(config)
    return config
PYEOF

    # --- notion_toolkit/utils.py ---
    cat > notion_toolkit/utils.py << 'PYEOF'
"""Utility functions."""
import re
import hashlib


def clean_notion_id(raw_id: str) -> str:
    """Normalize a Notion ID - strip dashes, validate format."""
    cleaned = raw_id.replace("-", "").strip()
    # Extract ID from URL if user pastes a full Notion URL
    url_match = re.search(r"([a-f0-9]{32})", cleaned)
    if url_match:
        return url_match.group(1)
    if len(cleaned) == 32 and all(c in "0123456789abcdef" for c in cleaned):
        return cleaned
    # TODO: better error message
    raise ValueError(f"Invalid Notion ID: {raw_id}")


def format_notion_id(raw_id: str) -> str:
    """Format a 32-char hex ID into Notion's 8-4-4-4-12 UUID format."""
    clean = clean_notion_id(raw_id)
    return f"{clean[:8]}-{clean[8:12]}-{clean[12:16]}-{clean[16:20]}-{clean[20:]}"


def truncate(text, max_len=80):
    """Truncate text with ellipsis."""
    if len(text) <= max_len:
        return text
    return text[:max_len - 3] + "..."


def file_hash(filepath):
    """Get SHA256 hash of a file for change detection."""
    h = hashlib.sha256()
    with open(filepath, "rb") as f:
        for chunk in iter(lambda: f.read(8192), b""):
            h.update(chunk)
    return h.hexdigest()[:16]
PYEOF

    # --- notion_toolkit/cli.py ---
    cat > notion_toolkit/cli.py << 'PYEOF'
"""Command-line interface for Notion Toolkit."""
import argparse
import sys
import json
from .client import NotionClient
from .exporter import NotionExporter
from .config import load_config, init_config


def cmd_export(args, config):
    """Export a Notion database to file."""
    client = NotionClient(config["api_key"], timeout=config.get("timeout", 30))
    exporter = NotionExporter(config.get("output_dir", "output"))

    print(f"Querying database {args.database_id}...")
    rows = client.query_database(args.database_id)
    print(f"Got {len(rows)} rows")

    if args.format == "json":
        path = exporter.export_json(rows, args.output or "export.json")
    elif args.format == "csv":
        path = exporter.export_csv(rows, args.output or "export.csv")
    else:
        print(f"Unknown format: {args.format}", file=sys.stderr)
        sys.exit(1)

    print(f"Exported to {path}")


def cmd_page(args, config):
    """Fetch and display a Notion page."""
    client = NotionClient(config["api_key"])
    page = client.get_page(args.page_id)

    if args.content:
        blocks = client.get_page_content(args.page_id)
        if args.format == "md":
            exporter = NotionExporter(config.get("output_dir", "output"))
            path = exporter.export_markdown(blocks)
            print(f"Exported to {path}")
        else:
            print(json.dumps(blocks, indent=2))
    else:
        print(json.dumps(page, indent=2))


def cmd_search(args, config):
    """Search Notion workspace."""
    # TODO: implement search
    print("Search not implemented yet")


def cmd_info(args, config):
    """Show database schema info."""
    client = NotionClient(config["api_key"])
    db = client.get_database(args.database_id)

    print(f"Database: {db.get('title', [{}])[0].get('plain_text', 'Untitled')}")
    print(f"URL: {db.get('url', 'N/A')}")
    print("\nProperties:")
    for name, prop in db.get("properties", {}).items():
        print(f"  {name}: {prop.get('type', '?')}")


def cmd_init(args, config):
    """Initialize configuration."""
    init_config()


def main():
    parser = argparse.ArgumentParser(
        prog="notion-toolkit",
        description="CLI tools for the Notion API"
    )
    parser.add_argument("--config", help="Path to config file")
    parser.add_argument("--verbose", "-v", action="store_true", help="Verbose output")
    subparsers = parser.add_subparsers(dest="command", help="Available commands")

    # export
    p_export = subparsers.add_parser("export", help="Export a database")
    p_export.add_argument("database_id", help="Notion database ID or URL")
    p_export.add_argument("--format", "-f", default="json", choices=["json", "csv"])
    p_export.add_argument("--output", "-o", help="Output filename")

    # page
    p_page = subparsers.add_parser("page", help="Fetch a page")
    p_page.add_argument("page_id", help="Notion page ID or URL")
    p_page.add_argument("--content", "-c", action="store_true", help="Include page content blocks")
    p_page.add_argument("--format", "-f", default="json", choices=["json", "md"])

    # search
    p_search = subparsers.add_parser("search", help="Search workspace")
    p_search.add_argument("query", help="Search query")
    p_search.add_argument("--type", "-t", choices=["page", "database"], help="Filter by type")

    # info
    p_info = subparsers.add_parser("info", help="Show database schema")
    p_info.add_argument("database_id", help="Notion database ID or URL")

    # init
    subparsers.add_parser("init", help="Initialize config")

    args = parser.parse_args()
    if not args.command:
        parser.print_help()
        sys.exit(0)

    config = load_config(args.config if hasattr(args, "config") else None)
    if args.command != "init" and not config.get("api_key"):
        print("No API key configured. Run 'notion-toolkit init' first.", file=sys.stderr)
        sys.exit(1)

    commands = {
        "export": cmd_export,
        "page": cmd_page,
        "search": cmd_search,
        "info": cmd_info,
        "init": cmd_init,
    }
    commands[args.command](args, config)


if __name__ == "__main__":
    main()
PYEOF

    # --- tests/__init__.py ---
    touch tests/__init__.py

    # --- tests/test_utils.py ---
    cat > tests/test_utils.py << 'PYEOF'
"""Tests for utility functions."""
import pytest
from notion_toolkit.utils import clean_notion_id, format_notion_id, truncate


def test_clean_notion_id_plain():
    assert clean_notion_id("a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6") == "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6"


def test_clean_notion_id_with_dashes():
    assert clean_notion_id("a1b2c3d4-e5f6-a7b8-c9d0-e1f2a3b4c5d6") == "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6"


def test_clean_notion_id_from_url():
    url = "https://notion.so/mypage-a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6"
    assert clean_notion_id(url) == "a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6"


def test_clean_notion_id_invalid():
    with pytest.raises(ValueError):
        clean_notion_id("not-a-valid-id")


def test_format_notion_id():
    result = format_notion_id("a1b2c3d4e5f6a7b8c9d0e1f2a3b4c5d6")
    assert result == "a1b2c3d4-e5f6-a7b8-c9d0-e1f2a3b4c5d6"


def test_truncate_short():
    assert truncate("hello", 10) == "hello"


def test_truncate_long():
    result = truncate("a" * 100, 20)
    assert len(result) == 20
    assert result.endswith("...")


# TODO: add tests for file_hash
PYEOF

    # --- pyproject.toml ---
    cat > pyproject.toml << 'PYEOF'
[build-system]
requires = ["setuptools>=68.0", "wheel"]
build-backend = "setuptools.backends._legacy:_Backend"

[project]
name = "notion-toolkit"
version = "0.3.1"
description = "CLI tools for the Notion API"
requires-python = ">=3.10"
dependencies = [
    "requests>=2.31.0",
    "python-dotenv>=1.0.0",
]

[project.optional-dependencies]
dev = [
    "pytest>=7.0",
    "pytest-cov>=4.0",
]

[project.scripts]
notion-toolkit = "notion_toolkit.cli:main"
PYEOF

    # --- .gitignore ---
    cat > .gitignore << 'GIEOF'
__pycache__/
*.pyc
*.pyo
*.egg-info/
dist/
build/
output/
.env
*.log
.notion-toolkit/
.pytest_cache/
.coverage
GIEOF

    # --- README.md ---
    cat > README.md << 'MDEOF'
# Notion Toolkit

CLI tools for working with the Notion API. Export databases, fetch pages, and search your workspace from the terminal.

## Installation

```bash
pip install -e .
```

## Setup

```bash
notion-toolkit init
```

You'll need a [Notion integration token](https://www.notion.so/my-integrations).

## Usage

```bash
# Export a database to JSON
notion-toolkit export <database-id> -f json

# Export to CSV
notion-toolkit export <database-id> -f csv -o tasks.csv

# Fetch a page
notion-toolkit page <page-id>

# Fetch page content as markdown
notion-toolkit page <page-id> --content -f md

# Show database schema
notion-toolkit info <database-id>

# Search workspace
notion-toolkit search "meeting notes"
```

## Development

```bash
pip install -e ".[dev]"
pytest
```

## Roadmap

- [x] Database export (JSON/CSV)
- [x] Page fetching
- [ ] Markdown export (in progress)
- [ ] Database sync/watch mode
- [ ] Batch operations
- [ ] Template support
- [ ] Rate limiting

## License

MIT
MDEOF

    git add -A && git commit -q -m "Initial commit: notion-toolkit CLI for Notion API"
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
CLAUDE_MODEL="claude-opus-5-5"
CLAUDE_EFFORT="low"
ENVEOF
    chmod 600 "$INSTALL_DIR/config.env"
    success "Config written (permissions: 600)"

    create_prompts "$INSTALL_DIR/prompts"
    success "Prompt pool created (18 prompts)"

    create_runner_script
    success "Runner script created"

    create_project_scaffold
    success "Project scaffold initialized"
}

install_cron() {
    info "Installing cron job..."
    local cron_line="$CRON_SCHEDULE /bin/bash $INSTALL_DIR/runner.sh"
    (crontab -l 2>/dev/null | grep -v "notion-toolkit/runner.sh" || true; echo "$cron_line") | crontab -
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
    echo -e "  $(crontab -l 2>/dev/null | grep runner)"
    echo ""
    echo -e "${BOLD}── Commands ──${NC}"
    echo ""
    echo -e "  Test run:       ${DIM}bash ~/notion-toolkit/runner.sh${NC}"
    echo -e "  View logs:      ${DIM}tail -f ~/notion-toolkit/logs/*.log${NC}"
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
    if crontab -l 2>/dev/null | grep -q "runner.sh"; then
        success "Cron active"
        echo -e "  $(crontab -l 2>/dev/null | grep runner)"
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
    (crontab -l 2>/dev/null | grep -v "notion-toolkit/runner.sh" || true) | crontab -
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
    install_deps
    collect_input
    create_structure
    install_cron
    show_summary

    read -rp "$(echo -e "${CYAN}Run a test now?${NC} [Y/n] ")" rt
    if [[ ! "$rt" =~ ^[Nn]$ ]]; then
        info "Running test..."
        bash "$INSTALL_DIR/runner.sh" && success "Test done! Check logs." || warn "Test had warnings, check logs."
    fi
    echo ""
    success "All set! Dev environment is running on schedule."
    echo ""
}

main "$@"
