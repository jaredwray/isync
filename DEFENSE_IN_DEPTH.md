# Defense in Depth

Tracking against https://github.com/jaredwray/agentic/blob/main/skills/security/defense-in-depth-nodejs/SKILL.md.

Profile: macOS app (Swift) · public

This repository is a Swift package, not a Node.js package. The catalog has no Swift version, so
this file adapts it:

- Section 2 omits the Safe Chain and cloud environment items, because the repository has no
  `pnpm-lock.yaml`. It omits the Dev Container item, because the repository has no
  `devcontainer.json`.
- Section 3 uses Swift Package Manager equivalents of the pnpm items.
- Section 5 is omitted, because the app is not an npm library.
- An item that does not apply to a Swift repository is checked with a "not applicable" note.

## 1. Security docs
- [x] `SECURITY.md` present — contact info + "How this repository is secured" summary — PR #1
- [x] `DEFENSE_IN_DEPTH.md` present (this file) — PR #2

## 2. CODEOWNERS and cloud bootstrap
- [ ] `.github/CODEOWNERS` covers `/.github/`, `/.vscode/`, `/.cursor/`, `/.devcontainer/`, `/.claude/`, `/.codex/`, `/scripts/` with owners the maintainer names

## 3. Dependencies (Swift Package Manager)
- [x] No third-party dependencies in the repository; a new dependency needs an approved ADR in `docs/adr/` — verified 2026-10-22
- [ ] A new dependency is pinned with `exact:` to a release at least 7 days old, and `Package.resolved` is committed
- [ ] CI builds with `swift build --disable-automatic-resolution`, so CI fails if the resolved versions would change (PR #3 pending)
- [x] No `.github/dependabot.yml`; other dependency-update tools (if any) open PRs only — never auto-merge — verified 2026-10-22

## 4. GitHub Actions
- [x] `permissions: contents: read` (or `{}` + per-job grants) on every workflow — PR #2
- [x] No `contents: write` except jobs whose purpose is mutating the repo (GitHub Release); generated output is a workflow artifact, never committed back from CI — PR #2
- [x] Every action pinned to a full commit SHA, verified against the release tag — PR #2
- [x] Every job installs Socket Firewall — not applicable: no job runs `npm`, `pnpm`, or another package manager that Socket Firewall wraps
- [x] `.github/workflows/check-workflows.yaml` lints workflows with zizmor on every PR; the zizmor action and the zizmor version are pinned — PR #2
- [x] Workflow `name:` and job `name:` contain no spaces (kebab-case) so they can be set as required status checks — PR #2
- [x] `persist-credentials: false` on checkouts that don't push — PR #2
- [x] No `pull_request_target` on workflows that run untrusted PR code — PR #2
- [ ] Release workflows do not restore a `.build` or SwiftPM cache (applies when a release workflow exists)
- [x] No registry credentials in Actions secrets — verified 2026-10-22

## 6. Security tooling
- [x] Aikido runs on every build — verified 2026-10-22 (check on PR #1)
- [ ] Aikido release gate: a release workflow's publish job `needs:` a passing `scan-release` (applies when a release workflow exists)
- [x] Socket reviews every PR that changes dependencies — verified 2026-10-22 (check on PR #1)

## 7. Repository lockdown
- [ ] Phishing-resistant 2FA (passkeys / hardware keys) on the GitHub account (manual)
- [ ] Recovery codes stored offline in a password manager (manual)
- [ ] `lockdown-repo.sh` applied by a repo admin (never committed to this repo); `--check` with `--required-checks` and `--allowed-actions` passes (PRs required on the default branch, merges blocked unless required status checks pass — include the `zizmor` code scanning result, because the zizmor job passes in SARIF mode even with findings — tag ruleset, immutable releases, fork-PR approval, read-only workflow tokens, Actions allowlist, secret scanning, Dependabot disabled, private vulnerability reporting)
