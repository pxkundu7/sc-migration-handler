# GitHub Migration Plan

## Objective
Migrate 50+ repositories from an on-premises GitHub Enterprise Server to GitHub.com, using a dedicated migration repository.

## Steps
1. **Inventory**: Run `scripts/inventory.sh` to list repositories.
2. **Organization Setup**: Run `scripts/org_setup.sh` to configure GitHub.com organization.
3. **Dry Run**: Run `scripts/dry_run.sh` to test migration on a subset of repositories.
4. **Production Migration**: Run `scripts/production_migration.sh` during a maintenance window.
5. **Post-Migration**: Run `scripts/post_migration.sh` to finalize workflows and decommission the on-prem server.

## Security
- Use `config/.env` for sensitive variables.
- Enable SAML SSO and 2FA on GitHub.com.
- Restrict access to `migration-repo` to admins.

## Timeline
- Planning: 1-2 weeks
- Dry Run: 1-2 days
- Production Migration: 1 day
- Post-Migration: 1-2 weeks
