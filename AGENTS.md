# Repository Guidelines

## Project Structure & Module Organization
- `apps/`: Kustomize bases + prod overlays for Ghost, ingress-nginx, cloudflared, observers, probes. Edit overlays first for behavior changes.
- `clusters/prod/`: Argo CD `AppProject` and child `Application` manifests (App-of-Apps entrypoint).
- `iac/argocd/`: Root Argo CD application.
- `security/`: Vault stack plus Vault Secrets Operator (operator + resources).
- `config/`: Env values (`dev.env`, `prod.env`); never store real secrets here.
- `scripts/`: Operational helpers (`bootstrap.sh`, `health-check.sh`, `validate.sh`); run from repo root.
- `docs/`: English/Korean guides tied to manifests.
- `migration/`: Hugo→Ghost content migration helper.

## Build, Test, and Development Commands
- `make validate` (preferred): Builds prod overlays and runs kubeconform across apps and security stacks.
- `./scripts/validate.sh`: Same checks, sectioned output; respects `KUSTOMIZE`/`KUBECONFORM` overrides.
- `./scripts/bootstrap.sh`: Bootstrap after cloning and updating Git URLs/domains.
- `./scripts/health-check.sh`: Status checks once the cluster is live.
- `./scripts/quick-reset.sh`: Fast restart of app pods; avoids full reinstall.

## Coding Style & Naming Conventions
- Manifests: YAML with 2-space indentation, lowercase `kebab-case` resource names, keep labels/annotations consistent with existing manifests.
- Overlays: Place prod changes in `overlays/prod`; avoid editing bases unless behavior should apply to all environments.
- Secrets: Never commit live tokens or Vault data. Use placeholders and document Vault paths in `docs/en`.
- Scripts: Bash with `set -euo pipefail`; keep functions small and idempotent.

## Testing Guidelines
- Validate every change with `make validate` (or `./scripts/validate.sh`). Ensure both Kustomize build and kubeconform schema checks pass.
- For new resources, add minimal probes and resource requests/limits consistent with similar components.
- If adding a new overlay, include it in `Makefile`/validation scripts so CI and local runs cover it.

## Commit & Pull Request Guidelines
- Commit messages follow Conventional Commit style seen in history (`feat(scope): ...`, `fix: ...`, `docs: ...`).
- PRs should include: what changed, why, validation results (`make validate` output), and any operational notes (e.g., new Vault secrets or DNS entries).
- Link related docs you updated; attach screenshots/logs only when clarifying behavior (Ingress, Cloudflare, or Vault changes).
- Keep PRs focused: one feature/fix per PR; avoid bundling unrelated manifest and doc changes.

## Security & Configuration Tips
- Store real secrets only in Vault; use Vault Secrets Operator for Kubernetes secret materialization.
- Cloudflare Tunnel is the default ingress path—avoid exposing NodePorts/LoadBalancers unless explicitly required.
- When changing domains or Git URLs, follow `docs/en/CUSTOMIZATION.md` and update `config/*.env` plus Argo CD root app references.

## Documentation Style
- Write in a dry, list-first, concise tone; prioritize clarity over length.
- Keep Markdown simple; avoid heavy formatting and only use bold when absolutely necessary.
- Do not use emojis; avoid language that sounds generated.
- Emphasize readability so contributors want to read the docs; short, direct instructions over prose.
