#!/usr/bin/env bash
# Writes a short build report to the `ci-logs` branch, so build results can be read with plain git.
# Usage: scripts/publish-ci-log.sh <name> <status>
# Never fails the job: a missing report is better than a red build for the wrong reason.
set -u
name="${1:-build}"
status="${2:-unknown}"
report="$(mktemp)"

{
  echo "workflow: ${name}"
  echo "status: ${status}"
  echo "commit: ${GITHUB_SHA:-unknown}"
  echo "ref: ${GITHUB_REF_NAME:-unknown}"
  echo "run: ${GITHUB_SERVER_URL:-}/${GITHUB_REPOSITORY:-}/actions/runs/${GITHUB_RUN_ID:-}"
  echo "date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  for log in logs/*.log; do
    [ -f "$log" ] || continue
    echo
    echo "===== ${log}: problems ====="
    grep -nE "Executed [0-9]+ tests|error:|fatal error:|BUILD FAILED|\*\* [A-Z ]+ FAILED \*\*|Test Case .* failed|XCTAssert|::error::" "$log" | head -n 150 || true
    echo
    echo "===== ${log}: last 60 lines ====="
    tail -n 60 "$log"
  done
} > "$report"

if [ -z "${GITHUB_TOKEN:-}" ] || [ -z "${GITHUB_REPOSITORY:-}" ]; then
  cat "$report"
  exit 0
fi

remote="https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git"
for attempt in 1 2 3 4; do
  dir="$(mktemp -d)"
  (
    cd "$dir" || exit 1
    git init -q
    git remote add origin "$remote"
    if git fetch -q --depth=1 origin ci-logs 2>/dev/null; then
      git checkout -q -b ci-logs FETCH_HEAD
    else
      git checkout -q --orphan ci-logs
    fi
    cp "$report" "${name}.txt"
    git add "${name}.txt"
    git -c user.name="github-actions[bot]" -c user.email="41898282+github-actions[bot]@users.noreply.github.com" \
      commit -q -m "${name}: ${status} (${GITHUB_SHA:-})" || exit 0
    git push -q origin HEAD:ci-logs
  ) && exit 0
  sleep $((attempt * 3))
done
echo "Couldn't publish the build report; continuing."
exit 0
