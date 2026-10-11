# Claude Code Keepalive

One-script automated keepalive for Claude Code on VPS. Interactive setup, zero config files to edit manually.

## Quick Start

```bash
git clone https://github.com/kejicode/notion-toolkit.git
cd claude-keepalive
bash setup.sh
```

Or run directly:

```bash
curl -fsSL https://raw.githubusercontent.com/kejicode/notion-toolkit/main/setup.sh | bash
```

## What It Does

- Sets up an automated cron job that periodically runs Claude Code against a project
- Randomly selects from a pool of 18 project-specific dev prompts (code, bugfix, refactor, test, review)
- Adds random jitter (0-5 min) between runs to avoid pattern detection
- Generates a Notion Toolkit project scaffold with git history for realistic telemetry
- Logs everything with automatic rotation

## Setup Flow

```
$ bash setup.sh

   _____ _                 _        _  __                    _ _
  / ____| |               | |      | |/ /                  | (_)
 ...

[*] Checking environment...
[✓] Claude Code CLI found

── Configuration ──

Account label [acc-vps01-38271]:
Setup Token (input hidden): ****
Run interval [1]:
Task timeout (sec) [180]:
Log retention (days) [7]:

[✓] Config written (permissions: 600)
[✓] Prompt pool created (10 prompts)
[✓] Keepalive script created
[✓] Project scaffold initialized
[✓] Cron installed: 0 */2 * * *

── Installation Summary ──

  Account:     acc-vps01-38271
  Schedule:    0 */2 * * *
  ...

[✓] All set!
```

## Management

```bash
# Check if it's running
bash setup.sh --status

# Update token without reinstalling
bash setup.sh --update-token

# Remove everything
bash setup.sh --uninstall
```

## Architecture

```
~/claude-keepalive/
├── config.env          # Account config (chmod 600)
├── keepalive.sh        # Cron-executed runner
├── prompts/            # Random prompt pool (10 prompts)
│   ├── 01.txt ... 10.txt
├── logs/               # Auto-rotated daily logs
│   └── acc-xxx_20261012.log
└── project/            # Git-initialized scaffold project
    ├── main.py
    ├── utils.py
    └── ...
```

## Multiple Accounts

One VPS = one account. Clone the repo to each VPS and run `setup.sh`:

```bash
# From your local machine
for host in vps1 vps2 vps3; do
    ssh $host "git clone https://github.com/kejicode/notion-toolkit.git && cd claude-keepalive && bash setup.sh"
done
```

## License

MIT
