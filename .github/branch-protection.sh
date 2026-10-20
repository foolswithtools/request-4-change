#!/usr/bin/env bash
# Applies branch protection to main of this repo (prebutton spec D-021):
# one approving review from a CODEOWNER, admins included, no force pushes
# or deletions, no required status checks (this repo has no CI, D-023).
# A new push dismisses earlier approvals, and the last push must be
# approved by someone other than its pusher (D-080).
# --no-enforce-admins lets admins bypass the rules (D-051): needed only while
# the only CODEOWNER is also the author of every PR, since GitHub never lets
# an author approve their own PR.
#
# Usage: .github/branch-protection.sh <owner/repo> [--no-enforce-admins]
# Needs gh authenticated with admin rights on the repo.
set -euo pipefail

usage() {
  echo "Usage: .github/branch-protection.sh <owner/repo> [--no-enforce-admins]" >&2
  exit 2
}

[ "$#" -ge 1 ] || usage
repo="$1"; shift
case "$repo" in
  */*) ;;
  *) usage ;;
esac

enforce_admins=true
while [ "$#" -gt 0 ]; do
  case "$1" in
    --no-enforce-admins)
      enforce_admins=false; shift ;;
    *) usage ;;
  esac
done

body="{\"required_status_checks\":null,\"enforce_admins\":$enforce_admins,\"required_pull_request_reviews\":{\"required_approving_review_count\":1,\"require_code_owner_reviews\":true,\"dismiss_stale_reviews\":true,\"require_last_push_approval\":true},\"restrictions\":null,\"allow_force_pushes\":false,\"allow_deletions\":false}"

printf '%s\n' "$body" | gh api -X PUT "repos/$repo/branches/main/protection" \
  -H "Accept: application/vnd.github+json" --input -
