# GitHub Migration Project

This repository manages the migration of 50+ repositories from an on-premises GitHub Enterprise Server to GitHub.com.

## Structure
- `scripts/`: Bash scripts for migration tasks.
- `config/`: Configuration files (e.g., .env).
- `data/`: Inventory and migration data.
- `logs/`: Migration and validation logs.
- `docs/`: Documentation and guides.

## Usage
1. Copy `config/.env.example` to `config/.env` and update variables.
2. Run scripts from the `scripts/` directory.

## Security
- Do not commit `config/.env` or sensitive data.
- Use restrictive permissions for sensitive files.
