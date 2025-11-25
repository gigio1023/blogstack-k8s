# Contributing

## Commit messages
- Use Conventional Commit format: `type(scope): summary` (e.g., `feat(monitoring): isolate exporter credentials`).
- Always write a descriptive body:
  - **Why**: the problem or risk addressed.
  - **What**: concrete changes (files/resources, key values, new secrets/policies).
  - **Validation**: commands run or note if not run.
  - **Follow-up/ops**: manual steps (Vault secrets, DNS, migrations) required after merge.
- Keep one concern per commit; split infra vs docs when it adds clarity.

## Validation
- Preferred: `make validate` (or `./scripts/validate.sh`).
- Note any skipped checks with a short reason.

## Style
- Manifests: YAML 2-space indent, kebab-case names, follow existing labels/annotations.
- Secrets: no live credentials in Git; use Vault paths and document them in `docs/en`/`docs/ko`.

## PRs
- Summarize what/why, list validation results, and call out operational notes (new Vault paths, DNS, ingress changes).
