#!/usr/bin/env bash
# Replace the `screenshots` branch with a single commit holding the latest screenshots
# and a README that shows them, so they're viewable from the GitHub app on a phone.
# The branch is force-pushed each time, so it never accumulates history.
# Usage: publish-screenshots.sh <dir-with-pngs> [branch] [title]
# (needs GITHUB_TOKEN with contents: write). Each platform publishes to its own branch.
set -euo pipefail
branch=${2:-screenshots}
title=${3:-SunClock screenshots}
cd "$1"
{
  echo "# $title"
  echo
  echo "From \`${GITHUB_REF_NAME}\` at ${GITHUB_SHA:0:7}, $(date -u '+%Y-%m-%d %H:%M UTC'). Replaced on every push."
  for f in *.png; do
    echo
    echo "### ${f%.png}"
    echo
    echo "<img src=\"$f\" width=\"320\">"
  done
  if compgen -G "app-store/*.png" >/dev/null; then
    echo
    echo "## App Store set (6.9\" iPhone)"
    for f in app-store/*.png; do
      echo
      echo "<img src=\"$f\" width=\"240\">"
    done
  fi
} > README.md
git init -q -b "$branch"
git config user.name "github-actions[bot]"
git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
git add .
git commit -qm "Screenshots for ${GITHUB_SHA}"
git push -qf "https://x-access-token:${GITHUB_TOKEN}@github.com/${GITHUB_REPOSITORY}.git" "$branch"
echo "published to the $branch branch"
