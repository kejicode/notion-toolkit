# Notion Toolkit

CLI tools for the Notion API. Export databases, fetch pages, and search your workspace from the terminal.

## Installation

```bash
git clone https://github.com/kejicode/notion-toolkit.git
cd notion-toolkit
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
- [x] Database schema inspection
- [ ] Markdown export (in progress)
- [ ] Database sync/watch mode
- [ ] Batch operations
- [ ] Template support
- [ ] Rate limiting
- [ ] Multiple workspace support

## License

MIT
