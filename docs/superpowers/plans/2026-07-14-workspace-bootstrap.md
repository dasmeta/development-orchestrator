# Workspace Bootstrap And Repository Reconciliation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a local-first, two-phase workspace bootstrap workflow that discovers Git repositories, validates an operator-approved topology proposal, safely materializes it, and maintains portable repository indexes for onboarding and refresh.

**Architecture:** An LLM-facing `workspace-bootstrap` skill owns questions and classification. Small POSIX shell actions own deterministic inventory, comparison, validation, rendering, and apply behavior; JSON schemas and generated Markdown preserve portable workspace truth without treating LLM output as executable until validation and approval.

**Tech Stack:** POSIX-oriented Bash, Git, `jq`, `rg`, JSON Schema documents, Markdown, GitHub Actions shell tests.

---

## File Map

- Create `scripts/orchestration/lib/workspace_bootstrap.sh` for shared hashing, path, remote-host, and proposal helpers.
- Create `scripts/orchestration/discover-workspace.sh` for read-only local Git inventory.
- Create `scripts/orchestration/compare-workspace-inventory.sh` for onboarding and refresh deltas.
- Create `scripts/orchestration/validate-workspace-proposal.sh` for semantic validation and approval tokens.
- Create `scripts/orchestration/render-workspace-files.sh` for portable and human-readable indexes.
- Create `scripts/orchestration/apply-workspace-proposal.sh` for guarded materialization and journaling.
- Create `schemas/workspace-proposal.schema.json` and `schemas/repository-index.schema.json`.
- Create `templates/workspace/WORKSPACE.md` and `templates/workspace/repository-index.md`.
- Create `.agents/skills/workspace-bootstrap/SKILL.md` and `docs/runbooks/workspace-bootstrap.md`.
- Create focused shell tests under `tests/orchestration/`.
- Modify `README.md`, `AI-INDEX.md`, `TODO.md`, and `.github/workflows/control-repo-ci.yml`.

### Task 1: Shared Test Fixtures And Local Repository Discovery

**Files:**
- Create: `tests/helpers/git-fixtures.sh`
- Create: `tests/orchestration/test-discover-workspace.sh`
- Create: `scripts/orchestration/lib/workspace_bootstrap.sh`
- Create: `scripts/orchestration/discover-workspace.sh`

- [ ] **Step 1: Add a local Git fixture helper**

```bash
create_git_repo() {
  local path="$1"
  local remote_url="${2:-}"
  mkdir -p "$path"
  git -C "$path" init -q
  git -C "$path" config user.email test@example.test
  git -C "$path" config user.name "Test User"
  printf '# %s\n' "$(basename "$path")" > "$path/README.md"
  git -C "$path" add README.md
  git -C "$path" commit -qm "initial"
  if [[ -n "$remote_url" ]]; then
    git -C "$path" remote add origin "$remote_url"
  fi
}
```

- [ ] **Step 2: Write the failing discovery test**

Create GitHub, GitLab, Bitbucket, self-hosted, local-only, and dirty repositories, plus excluded orchestrator and `node_modules` repositories. Run discovery and assert:

```bash
jq -e '.schema_version == 1' "$inventory" >/dev/null
jq -e '.repositories | length == 5' "$inventory" >/dev/null
jq -e '.repositories[] | select(.name == "requirements") | .forge == "github.com"' "$inventory" >/dev/null
jq -e '.repositories[] | select(.name == "contracts") | .forge == "gitlab.com"' "$inventory" >/dev/null
jq -e '.repositories[] | select(.name == "e2e") | .forge == "bitbucket.org"' "$inventory" >/dev/null
jq -e '.repositories[] | select(.name == "backend") | .forge == "git.example.test"' "$inventory" >/dev/null
jq -e '.repositories[] | select(.name == "dirty") | .dirty == true' "$inventory" >/dev/null
jq -e '.repositories | all(.name != "orchestrator" and .name != "ignored")' "$inventory" >/dev/null
jq -e '.fingerprint | test("^[a-f0-9]{64}$")' "$inventory" >/dev/null
```

- [ ] **Step 3: Verify RED**

Run: `bash tests/orchestration/test-discover-workspace.sh`

Expected: FAIL because `discover-workspace.sh` does not exist.

- [ ] **Step 4: Implement shared helpers**

```bash
sha256_stream() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum | awk '{print $1}'
  else
    shasum -a 256 | awk '{print $1}'
  fi
}

absolute_path() {
  (cd "$1" 2>/dev/null && pwd -P)
}

remote_host() {
  local url="$1"
  case "$url" in
    file://*|/*|./*|../*) printf 'local\n' ;;
    *@*:* ) printf '%s\n' "$url" | sed -E 's#^[^@]+@([^:]+):.*#\1#' ;;
    *://* ) printf '%s\n' "$url" | sed -E 's#^[a-zA-Z][a-zA-Z0-9+.-]*://([^/@]+@)?([^/:]+).*#\2#' ;;
    * ) printf 'unknown\n' ;;
  esac
}
```

- [ ] **Step 5: Implement discovery**

Parse repeatable `--search-root`, required `--workspace-root`, and `--output`. Require `git` and `jq`. Find `.git` files and directories while pruning `.git`, `node_modules`, `.worktrees`, and `vendor`; canonicalize and deduplicate roots; exclude the orchestrator; capture branch, dirty state, all remotes, forge host, and README/AGENTS/AI-INDEX signals. Sort by path and hash canonical `.repositories` JSON into `.fingerprint`. Write the output atomically.

- [ ] **Step 6: Verify GREEN and commit**

```bash
bash tests/orchestration/test-discover-workspace.sh
git add tests/helpers/git-fixtures.sh tests/orchestration/test-discover-workspace.sh scripts/orchestration/lib/workspace_bootstrap.sh scripts/orchestration/discover-workspace.sh
git commit -m "feat: discover local workspace repositories"
```

### Task 2: Proposal And Repository Index Contracts

**Files:**
- Create: `schemas/workspace-proposal.schema.json`
- Create: `schemas/repository-index.schema.json`
- Create: `tests/orchestration/test-validate-workspace-proposal.sh`
- Create: `scripts/orchestration/validate-workspace-proposal.sh`

- [ ] **Step 1: Write the failing validator test**

Create one approved proposal with two repositories, one stage, no unresolved questions, and confirmed approval. Require validation success and a token matching `^[a-f0-9]{64}$`. Create invalid variants and require failure for duplicate IDs, duplicate targets, traversal targets, unknown dependencies, unknown stage repositories, clone without origin, unresolved questions, and dirty move without `allow_dirty`.

- [ ] **Step 2: Verify RED**

Run: `bash tests/orchestration/test-validate-workspace-proposal.sh`

Expected: FAIL because validator and schemas do not exist.

- [ ] **Step 3: Add JSON schemas**

Require this top-level proposal shape:

```json
{
  "schema_version": 1,
  "proposal_id": "bootstrap-001",
  "status": "approved",
  "inventory_fingerprint": "64-character hash",
  "workspace": {"name": "Example", "description": "Example workspace", "root": "/local/root"},
  "repositories": [],
  "stages": [],
  "routing_notes": [],
  "unresolved_questions": [],
  "allow_update": false,
  "approval": {"confirmed": true, "confirmed_at": "2026-07-14T00:00:00Z"}
}
```

Repository entries require `id`, `name`, `role`, `description`, `authority`, `scope`, `dependencies`, `source_path`, `target_path`, `materialization`, `required`, `allow_dirty`, and `remotes`. Allow `move`, `symlink`, `clone`, and `keep`. Repository-index entries exclude local-only source and approval fields.

- [ ] **Step 4: Implement semantic validation**

Use `jq -e` with explicit stderr errors. Enforce unique IDs/targets, safe numbered targets, known dependency/stage repository IDs, clone origins, move/symlink sources, final-position keep entries, empty unresolved questions, and dirty-move approval. For `--print-token`, canonicalize `del(.approval)` using `jq -S -c` and hash with `sha256_stream`.

- [ ] **Step 5: Verify GREEN and commit**

```bash
bash tests/orchestration/test-validate-workspace-proposal.sh
git add schemas/workspace-proposal.schema.json schemas/repository-index.schema.json tests/orchestration/test-validate-workspace-proposal.sh scripts/orchestration/validate-workspace-proposal.sh
git commit -m "feat: validate workspace bootstrap proposals"
```

### Task 3: Portable Index And Workspace File Rendering

**Files:**
- Create: `templates/workspace/WORKSPACE.md`
- Create: `templates/workspace/repository-index.md`
- Create: `tests/orchestration/test-render-workspace-files.sh`
- Create: `scripts/orchestration/render-workspace-files.sh`

- [ ] **Step 1: Write the failing renderer test**

Render an approved proposal and assert all four generated files exist:

```bash
assert_file_exists "$out/config/repository-index.json"
assert_file_exists "$out/config/workspace.json"
assert_file_exists "$out/overlays/repository-index.md"
assert_file_exists "$out/WORKSPACE.md"
jq -e '.repositories.intent.target_path == "02-product-requirements"' "$out/config/repository-index.json" >/dev/null
jq -e '.repositories.intent.path == "../02-product-requirements"' "$out/config/workspace.json" >/dev/null
jq -e '.stages[0].repository == "intent"' "$out/config/workspace.json" >/dev/null
assert_contains "$out/overlays/repository-index.md" "Source of truth"
assert_contains "$out/WORKSPACE.md" "overlays/repository-index.md"
```

Also reject any occurrence of the local temporary source root in committed generated files.

- [ ] **Step 2: Verify RED**

Run: `bash tests/orchestration/test-render-workspace-files.sh`

Expected: FAIL because renderer and templates do not exist.

- [ ] **Step 3: Add templates and renderer**

The WORKSPACE template points agents to `config/workspace.json` and `overlays/repository-index.md`. The index template contains a generated warning and table headers. The renderer validates the proposal, builds a portable ID-keyed catalog after deleting local-only fields, builds workspace routing with `../<target_path>` paths, preserves stages and conservative merge defaults, and renders target-sorted Markdown rows and routing-note bullets. All writes use temporary files.

- [ ] **Step 4: Verify GREEN and commit**

```bash
bash tests/orchestration/test-render-workspace-files.sh
git add templates/workspace tests/orchestration/test-render-workspace-files.sh scripts/orchestration/render-workspace-files.sh
git commit -m "feat: render portable workspace repository indexes"
```

### Task 4: Inventory Comparison For Onboarding And Refresh

**Files:**
- Create: `tests/orchestration/test-compare-workspace-inventory.sh`
- Create: `scripts/orchestration/compare-workspace-inventory.sh`

- [ ] **Step 1: Write the failing comparison test**

Create an index where one repo is present, one is found elsewhere with the same remote, one is missing, and an unindexed repo exists. Assert `present`, `misplaced`, `missing`, `unindexed`, and `has_changes`. Add an exact-match case requiring `has_changes == false`.

- [ ] **Step 2: Verify RED**

Run: `bash tests/orchestration/test-compare-workspace-inventory.sh`

Expected: FAIL because comparator does not exist.

- [ ] **Step 3: Implement comparison**

Parse `--inventory`, `--index`, `--workspace-root`, and `--output`. Match indexed repos first by expected canonical target path and then by shared remote URL. Produce sorted `present`, `misplaced`, `missing`, `unindexed`, and `remote_mismatches` arrays. Set `has_changes` when any array except `present` is non-empty. Only write the requested delta file.

- [ ] **Step 4: Verify GREEN and commit**

```bash
bash tests/orchestration/test-compare-workspace-inventory.sh
git add tests/orchestration/test-compare-workspace-inventory.sh scripts/orchestration/compare-workspace-inventory.sh
git commit -m "feat: compare workspace inventories for refresh"
```

### Task 5: Guarded Proposal Application And Journaling

**Files:**
- Create: `tests/orchestration/test-apply-workspace-proposal.sh`
- Create: `scripts/orchestration/apply-workspace-proposal.sh`

- [ ] **Step 1: Write the failing apply test**

Create sources for move and symlink, a local bare remote for clone, and an already-positioned repo for keep. Verify dry-run immutability, missing/wrong confirmation failure, successful materialization, generated files, a complete journal, and harmless repeat apply. Add negative cases for collision, unapproved dirty move, mismatched existing remote, and unresolved questions.

- [ ] **Step 2: Verify RED**

Run: `bash tests/orchestration/test-apply-workspace-proposal.sh`

Expected: FAIL because apply action does not exist.

- [ ] **Step 3: Implement dry-run and preflight**

Support `--proposal`, `--dry-run`, `--confirm`, and `--print-token`. Always validate. Dry-run prints operation/source/target without creating any workspace content. Real apply requires approved state, confirmed approval, exact token, a valid root, safe unique targets, valid Git sources, approved dirty moves, clone origins, compatible existing targets, and explicit `allow_update` for differing active files. Render candidate generated files before mutation.

- [ ] **Step 4: Implement journaling and operations**

Write `workspace/bootstrap/<proposal_id>/apply-journal.json` with `in_progress` before mutation. Execute target-sorted operations using `mv`, `ln -s`, `git clone`, or verification for `keep`. Journal every completed operation atomically. On failure, reverse completed moves when safe, unlink created symlinks, preserve clones, and report `recovery_required` when anything remains. On success install rendered files, verify every target, and mark `complete`.

- [ ] **Step 5: Verify GREEN and commit**

```bash
bash tests/orchestration/test-apply-workspace-proposal.sh
git add tests/orchestration/test-apply-workspace-proposal.sh scripts/orchestration/apply-workspace-proposal.sh
git commit -m "feat: safely apply workspace bootstrap proposals"
```

### Task 6: LLM Bootstrap Skill And Operator Runbook

**Files:**
- Create: `.agents/skills/workspace-bootstrap/SKILL.md`
- Create: `docs/runbooks/workspace-bootstrap.md`
- Create: `tests/orchestration/test-workspace-bootstrap-guidance.sh`
- Modify: `README.md`
- Modify: `AI-INDEX.md`
- Modify: `TODO.md`

- [ ] **Step 1: Read and apply the available `skill-creator` instructions**

The workspace skill is a real reusable skill, so validate its frontmatter, triggers, workflow, stop conditions, and referenced command paths using the skill-authoring guidance before writing it.

- [ ] **Step 2: Write the failing guidance test**

Require the skill and runbook to cover local-first discovery; GitHub, GitLab, Bitbucket, self-hosted, and local remotes; the 00–05 taxonomy; one-at-a-time `needs-input` questions; dry-run; explicit confirmation token; dirty-repo confirmation; initial bootstrap, new-person setup, and refresh; both generated indexes; and the prohibition on silent move, clone, link, addition, or removal. Require README and AI-INDEX links.

- [ ] **Step 3: Verify RED**

Run: `bash tests/orchestration/test-workspace-bootstrap-guidance.sh`

Expected: FAIL because skill and runbook do not exist.

- [ ] **Step 4: Implement skill and runbook**

The skill defines initial bootstrap, new-person setup, and refresh. Each mode reads root guidance, discovers and compares, inspects child guidance read-only, drafts a schema-valid proposal, asks one question at a time, shows dry-run, requests explicit approval, prints and confirms the token, applies, and verifies. The runbook documents exact commands and recovery. README introduces workspace composition before feature delivery. AI-INDEX lists scripts, schemas, templates, generated outputs, and tests. TODO records hosted-forge discovery as the later adapter.

- [ ] **Step 5: Verify GREEN and commit**

```bash
bash tests/orchestration/test-workspace-bootstrap-guidance.sh
git add .agents/skills/workspace-bootstrap docs/runbooks/workspace-bootstrap.md tests/orchestration/test-workspace-bootstrap-guidance.sh README.md AI-INDEX.md TODO.md
git commit -m "docs: add workspace bootstrap operator workflow"
```

### Task 7: CI Integration And Full Verification

**Files:**
- Modify: `.github/workflows/control-repo-ci.yml`
- Modify: `tests/orchestration/test-workspace-bootstrap-guidance.sh`

- [ ] **Step 1: Add a failing CI-wiring assertion**

Require the CI workflow to invoke all six new focused tests. Run the guidance test and confirm it fails because CI is not wired.

- [ ] **Step 2: Add tests to CI and verify focused behavior**

```bash
bash tests/orchestration/test-discover-workspace.sh
bash tests/orchestration/test-validate-workspace-proposal.sh
bash tests/orchestration/test-render-workspace-files.sh
bash tests/orchestration/test-compare-workspace-inventory.sh
bash tests/orchestration/test-apply-workspace-proposal.sh
bash tests/orchestration/test-workspace-bootstrap-guidance.sh
```

Expected: all PASS without network.

- [ ] **Step 3: Run the complete suite**

```bash
for test_file in tests/orchestration/test-*.sh; do
  echo "RUN $test_file"
  bash "$test_file"
done
```

Expected: all tests exit 0.

- [ ] **Step 4: Run hygiene and conformance checks**

```bash
git diff --check
bash tests/orchestration/test-template-agnostic.sh
git status --short
```

Expected: no whitespace errors, template conformance passes, and only intended changes remain.

- [ ] **Step 5: Commit CI wiring**

```bash
git add .github/workflows/control-repo-ci.yml tests/orchestration/test-workspace-bootstrap-guidance.sh
git commit -m "ci: verify workspace bootstrap workflow"
```

- [ ] **Step 6: Review against the approved design**

Confirm every success criterion in `docs/superpowers/specs/2026-07-14-workspace-bootstrap-design.md` has a test or an explicit operator boundary. Hosted-forge discovery may remain in TODO; local discovery, approval, setup, refresh, and index generation may not.
