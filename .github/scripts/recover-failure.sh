#!/usr/bin/env bash
# .github/scripts/recover-failure.sh
#
# Post-merge CI failure recovery:
#   1. Identifies the merged PR that caused the failure
#   2. Creates a recovery branch preserving original work
#   3. Creates a revert PR restoring main
#   4. Creates a recovery PR from the recovery branch
#   5. Posts a comment on the original PR
#
# Required env vars: GH_TOKEN, WORKFLOW_RUN_ID, WORKFLOW_RUN_URL,
#                    WORKFLOW_NAME, COMMIT_SHA, GITHUB_REPOSITORY (set by Actions)
set -Eeuo pipefail

# ─── Configuration ──────────────────────────────────────────────────
REPO="${GITHUB_REPOSITORY}"
MAIN_BRANCH="main"
RECOVERY_PREFIX="recovery"
REVERT_PREFIX="revert"

log() { echo "[recovery] $*"; }

# ─── GitHub API helpers ─────────────────────────────────────────────

# Find the merged PR number associated with a commit SHA.
find_merged_pr_number() {
  local sha="$1"
  gh api "repos/${REPO}/commits/${sha}/pulls" \
    --jq '.[] | select(.merged_at != null) | .number' \
    2>/dev/null | head -1
}

# Check if a remote branch exists (returns 0 if exists, 1 if not).
remote_branch_exists() {
  local branch="$1"
  gh api "repos/${REPO}/branches/${branch}" --silent 2>/dev/null
}

# Check if an open PR with a given head branch prefix exists.
# Returns PR number if found, empty string otherwise.
open_pr_with_head_prefix() {
  local head_prefix="$1"
  gh pr list --repo "${REPO}" \
    --search "head:${head_prefix}" \
    --state open \
    --limit 1 \
    --json number \
    --jq '.[0].number // ""' 2>/dev/null || echo ""
}

# Ensure a label exists, create it if not.
ensure_label() {
  local label="$1"
  local color="${2:-e11d48}"
  local desc="${3:-Automated revert PR}"
  gh label create "${label}" --repo "${REPO}" \
    --color "${color}" --description "${desc}" \
    --force 2>/dev/null || true
}

# ─── Main logic ─────────────────────────────────────────────────────

log "Starting post-merge failure recovery"
log "Workflow run: ${WORKFLOW_RUN_URL}"
log "Commit SHA:   ${COMMIT_SHA}"

# ── Step 1: Find the merged PR ──────────────────────────────────────
PR_NUMBER=$(find_merged_pr_number "${COMMIT_SHA}")
if [[ -z "${PR_NUMBER}" ]]; then
  log "No merged PR found for commit ${COMMIT_SHA}."
  log "This may be a direct push to main — skipping recovery."
  exit 0
fi
log "Found merged PR: #${PR_NUMBER}"

# ── Idempotency checks ─────────────────────────────────────────────
# Skip entirely if a revert PR already exists for this PR number.
EXISTING_REVERT=$(open_pr_with_head_prefix "${REVERT_PREFIX}/pr-${PR_NUMBER}")
if [[ -n "${EXISTING_REVERT}" ]]; then
  log "Revert PR already exists for #${PR_NUMBER}: #${EXISTING_REVERT}. Skipping."
  exit 0
fi

# ── Step 2: Get PR details ──────────────────────────────────────────
PR_JSON=$(gh pr view "${PR_NUMBER}" --repo "${REPO}" \
  --json 'title,author,headRefName,mergeCommit,mergedAt')

PR_TITLE=$(echo "${PR_JSON}" | jq -r '.title')
PR_AUTHOR=$(echo "${PR_JSON}" | jq -r '.author.login // "unknown"')
PR_HEAD_BRANCH=$(echo "${PR_JSON}" | jq -r '.headRefName // ""')
MERGE_COMMIT=$(echo "${PR_JSON}" | jq -r '.mergeCommit.oid // ""')
MERGED_AT=$(echo "${PR_JSON}" | jq -r '.mergedAt // "unknown"')

log "PR title:        ${PR_TITLE}"
log "PR author:       ${PR_AUTHOR}"
log "Original branch: ${PR_HEAD_BRANCH}"
log "Merge commit:    ${MERGE_COMMIT}"

# Validate: we need a merge commit to revert.
# Rebase-merge PRs don't have a single merge commit.
if [[ -z "${MERGE_COMMIT}" ]]; then
  log "ERROR: No merge commit found for PR #${PR_NUMBER}."
  log "This may be a rebase-merge — cannot revert automatically."
  log "Posting error comment on PR..."
  gh pr comment "${PR_NUMBER}" --repo "${REPO}" --body \
    "⚠️ **Post-Merge CI Failure — Manual Recovery Needed**

CI failed after this PR was merged into \`${MAIN_BRANCH}\`, but no merge commit was found (possibly a rebase merge). Manual intervention required.

- **Failed run:** [View workflow run](${WORKFLOW_RUN_URL})"

  exit 1
fi

# ── Step 3: Fetch failed jobs and steps ─────────────────────────────
log "Fetching failed job details..."
FAILED_JOBS_JSON=$(gh api "repos/${REPO}/actions/runs/${WORKFLOW_RUN_ID}/jobs" \
  --jq '[.jobs[] | select(.conclusion == "failure")]')

FAILED_JOB_NAMES=$(echo "${FAILED_JOBS_JSON}" | jq -r '.[].name' | tr '\n' ', ' | sed 's/,$//')
log "Failed jobs: ${FAILED_JOB_NAMES}"

# Build detailed steps summary for each failed job
FAILED_STEPS_SUMMARY=""
JOB_COUNT=$(echo "${FAILED_JOBS_JSON}" | jq 'length')
for ((i = 0; i < JOB_COUNT; i++)); do
  JOB_NAME=$(echo "${FAILED_JOBS_JSON}" | jq -r ".[$i].name")
  JOB_ID=$(echo "${FAILED_JOBS_JSON}" | jq -r ".[$i].id")

  FAILED_STEPS_SUMMARY+="### Job: \`${JOB_NAME}\`"$'\n'

  STEPS_JSON=$(echo "${FAILED_JOBS_JSON}" | jq ".[$i].steps | [.[] | select(.conclusion == \"failure\")]")

  STEP_COUNT=$(echo "${STEPS_JSON}" | jq 'length')
  if [[ "${STEP_COUNT}" -gt 0 ]]; then
    for ((s = 0; s < STEP_COUNT; s++)); do
      STEP_NAME=$(echo "${STEPS_JSON}" | jq -r ".[$s].name")
      STEP_NUMBER=$(echo "${STEPS_JSON}" | jq -r ".[$s].number")
      FAILED_STEPS_SUMMARY+="- **Step ${STEP_NUMBER}:** ${STEP_NAME}"$'\n'
    done
  else
    FAILED_STEPS_SUMMARY+="- (steps not retrievable)"$'\n'
  fi
done

# ── Step 4: Configure git ───────────────────────────────────────────
git config user.name "github-actions[bot]"
git config user.email "github-actions[bot]@users.noreply.github.com"

# ── Step 5: Create recovery branch ──────────────────────────────────
# The recovery branch preserves the exact tree from the merged PR,
# so it can be used as a base for follow-up fixes.
#
# Priority:
#   1. Original PR head branch (if it still exists on remote)
#   2. Merge commit SHA (always available, same tree)
RECOVERY_BRANCH="${RECOVERY_PREFIX}/pr-${PR_NUMBER}-ci-failure-fix"
RECOVERY_BRANCH_URL="https://github.com/${REPO}/tree/${RECOVERY_BRANCH}"
RECOVERY_SOURCE=""

if remote_branch_exists "${RECOVERY_BRANCH}"; then
  log "Recovery branch already exists: ${RECOVERY_BRANCH}"
  RECOVERY_SOURCE="existing"
elif [[ -n "${PR_HEAD_BRANCH}" ]] && remote_branch_exists "${PR_HEAD_BRANCH}"; then
  log "Creating recovery branch from original PR head branch: ${PR_HEAD_BRANCH}"
  git fetch origin "${PR_HEAD_BRANCH}"
  git checkout -b "${RECOVERY_BRANCH}" "origin/${PR_HEAD_BRANCH}"
  git push origin "${RECOVERY_BRANCH}"
  RECOVERY_SOURCE="pr-head-branch"
  log "Created recovery branch: ${RECOVERY_BRANCH} (from ${PR_HEAD_BRANCH})"
else
  log "Original PR head branch not found. Creating recovery branch from merge commit ${MERGE_COMMIT}..."
  git checkout -b "${RECOVERY_BRANCH}" "${MERGE_COMMIT}"
  git push origin "${RECOVERY_BRANCH}"
  RECOVERY_SOURCE="merge-commit"
  log "Created recovery branch: ${RECOVERY_BRANCH} (from merge commit)"
fi

# ── Step 6: Create revert branch and commit ─────────────────────────
REVERT_BRANCH="${REVERT_PREFIX}/pr-${PR_NUMBER}"

log "Creating revert branch from ${MAIN_BRANCH}..."
git fetch origin "${MAIN_BRANCH}"
git checkout -b "${REVERT_BRANCH}" "origin/${MAIN_BRANCH}"

# Determine parent count: merge commit has 2+ parents, squash has 1.
PARENT_COUNT=$(git rev-list --parents -n 1 "${MERGE_COMMIT}" | wc -w)
PARENT_COUNT=$((PARENT_COUNT - 1))

if [[ "${PARENT_COUNT}" -ge 2 ]]; then
  # Standard merge commit: revert with -m 1 to undo the merged tree
  log "Reverting merge commit (${PARENT_COUNT} parents) with -m 1..."
  if ! git revert -m 1 "${MERGE_COMMIT}" --no-edit; then
    log "ERROR: git revert failed. This may be due to merge conflicts."
    log "Manual revert required for commit ${MERGE_COMMIT}"
    exit 1
  fi
else
  # Squash merge: revert the single commit directly
  log "Reverting squash-merged commit (${PARENT_COUNT} parent)..."
  if ! git revert "${MERGE_COMMIT}" --no-edit; then
    log "ERROR: git revert failed. This may be due to merge conflicts."
    log "Manual revert required for commit ${MERGE_COMMIT}"
    exit 1
  fi
fi

git push origin "${REVERT_BRANCH}"

# ── Step 7: Ensure labels exist ─────────────────────────────────────
ensure_label "automated-revert"
ensure_label "ci-failure-fix" "f59e0b" "Fix after post-merge CI failure"

# ── Step 8: Create revert PR ────────────────────────────────────────
REVERT_PR_BODY=$(cat <<EOF
## Automated Revert — Post-Merge CI Failure

This PR reverts the changes from **#${PR_NUMBER}** that caused CI to fail on \`${MAIN_BRANCH}\`.

### Original PR
| Field | Value |
|-------|-------|
| **PR** | #${PR_NUMBER} — ${PR_TITLE} |
| **Author** | @${PR_AUTHOR} |
| **Merged at** | ${MERGED_AT} |

### Reverted Commit
\`${MERGE_COMMIT}\`

### Failure Details
| Field | Value |
|-------|-------|
| **Workflow** | ${WORKFLOW_NAME} |
| **Run** | [\#${WORKFLOW_RUN_ID}](${WORKFLOW_RUN_URL}) |
| **Failed jobs** | ${FAILED_JOB_NAMES} |

<details>
<summary>Failed steps (click to expand)</summary>

${FAILED_STEPS_SUMMARY}

</details>

### Recovery
A recovery branch and PR have been created so the original work can be fixed and reapplied.
See the comment on the original PR for links.

> **Note:** This revert PR requires **manual merge** once CI passes. Do not merge automatically.

---
*Created automatically by the post-merge recovery workflow.*
EOF
)

log "Creating revert PR..."
REVERT_PR_URL=$(gh pr create \
  --repo "${REPO}" \
  --base "${MAIN_BRANCH}" \
  --head "${REVERT_BRANCH}" \
  --title "revert: PR #${PR_NUMBER} due to failing post-merge CI" \
  --body "${REVERT_PR_BODY}" \
  --label "automated-revert")

log "Created revert PR: ${REVERT_PR_URL}"

# ── Step 9: Create recovery PR ──────────────────────────────────────
# The recovery PR is opened from the recovery branch against main.
# Its purpose is to provide a ready-to-fix PR that reintroduces the changes.
EXISTING_RECOVERY_PR=$(open_pr_with_head_prefix "${RECOVERY_BRANCH}")
if [[ -n "${EXISTING_RECOVERY_PR}" ]]; then
  log "Recovery PR already exists for #${PR_NUMBER}: #${EXISTING_RECOVERY_PR}. Skipping."
  RECOVERY_PR_URL="https://github.com/${REPO}/pull/${EXISTING_RECOVERY_PR}"
else
  RECOVERY_PR_BODY=$(cat <<EOF
## Recovery — Fix After Post-Merge CI Failure

This PR preserves the changes from **#${PR_NUMBER}** that were reverted due to a CI failure on \`${MAIN_BRANCH}\`.

**Goal:** Fix the failing CI and merge this PR to reintroduce the changes.

### Context
| Field | Value |
|-------|-------|
| **Original PR** | #${PR_NUMBER} — ${PR_TITLE} |
| **Original author** | @${PR_AUTHOR} |
| **Merge commit** | \`${MERGE_COMMIT}\` |
| **Recovery source** | ${RECOVERY_SOURCE} |

### Failure Details
| Field | Value |
|-------|-------|
| **Workflow** | ${WORKFLOW_NAME} |
| **Run** | [\#${WORKFLOW_RUN_ID}](${WORKFLOW_RUN_URL}) |
| **Failed jobs** | ${FAILED_JOB_NAMES} |

<details>
<summary>Failed steps (click to expand)</summary>

${FAILED_STEPS_SUMMARY}

</details>

### How to fix
1. Check out this branch locally: \`git fetch origin && git checkout ${RECOVERY_BRANCH}\`
2. Fix the issue that caused CI to fail
3. Push your fix to this branch
4. CI will run automatically — ensure it passes
5. Merge this PR into \`${MAIN_BRANCH}\`

### Related
- **Revert PR:** ${REVERT_PR_URL}

---
*Created automatically by the post-merge recovery workflow.*
EOF
  )

  log "Creating recovery PR..."
  RECOVERY_PR_URL=$(gh pr create \
    --repo "${REPO}" \
    --base "${MAIN_BRANCH}" \
    --head "${RECOVERY_BRANCH}" \
    --title "fix: PR #${PR_NUMBER} after failing post-merge CI" \
    --body "${RECOVERY_PR_BODY}" \
    --label "ci-failure-fix")

  log "Created recovery PR: ${RECOVERY_PR_URL}"
fi

# ── Step 10: Post comment on original PR ────────────────────────────
COMMENT_BODY=$(cat <<EOF
⚠️ **Post-Merge CI Failure Detected**

The CI workflow failed after this PR was merged into \`${MAIN_BRANCH}\`.

- **Failed run:** [View workflow run](${WORKFLOW_RUN_URL})
- **Revert PR:** ${REVERT_PR_URL}
- **Recovery PR:** ${RECOVERY_PR_URL}

**Next steps:** Use the [recovery PR](${RECOVERY_PR_URL}) to fix the issue and reintroduce the changes. The revert PR restores \`${MAIN_BRANCH}\` to a passing state.
EOF
)

log "Posting comment on original PR #${PR_NUMBER}..."
gh pr comment "${PR_NUMBER}" --repo "${REPO}" --body "${COMMENT_BODY}"

log "Recovery complete."
