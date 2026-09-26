#!/bin/zsh
# Rebases the current personal branch onto upstream's dev branch, which is
# where Boring Notch cuts its release candidates. Your own commits stay on top.
#
# Usage: tools/sync-upstream.sh [--push] [remote] [branch]
#   --push   then force-push (with lease) the rebased branch to its remote, i.e. your fork
#   remote   defaults to "upstream" when that remote exists, otherwise "origin"
#   branch   defaults to "dev"
set -euo pipefail

push=false
positional=()
for arg in "$@"; do
    case "$arg" in
        --push) push=true ;;
        -*) echo "Unknown option: $arg" >&2; exit 2 ;;
        *) positional+=("$arg") ;;
    esac
done
default_remote=origin
if git remote get-url upstream >/dev/null 2>&1; then
    default_remote=upstream
fi
remote=${positional[1]:-$default_remote}
upstream_branch=${positional[2]:-dev}
upstream="$remote/$upstream_branch"

cd "$(git rev-parse --show-toplevel)"
branch=$(git symbolic-ref --quiet --short HEAD) || { echo "Not on a branch." >&2; exit 1; }
if [[ "$branch" == "$upstream_branch" || "$branch" == "main" ]]; then
    echo "Switch to your personal branch first (currently on '$branch')." >&2
    exit 1
fi
if [[ -n "$(git status --porcelain --untracked-files=no)" ]]; then
    echo "Commit or stash your changes before syncing." >&2
    exit 1
fi

old_base=$(git merge-base HEAD "$upstream")
old_tag=$(git describe --tags --abbrev=0 --match 'v*' "$old_base" 2>/dev/null || echo "none")

# --force: upstream re-points its "nightly" tag on every nightly build.
git fetch --tags --force --prune "$remote"
# Keep the local mirror of the upstream branch current too (fast-forward only).
git fetch --quiet "$remote" "$upstream_branch:$upstream_branch" 2>/dev/null || true

new_tag=$(git describe --tags --abbrev=0 --match 'v*' "$upstream" 2>/dev/null || echo "none")
incoming=$(git rev-list --count "$old_base..$upstream")

if (( incoming == 0 )); then
    echo "Already up to date with $upstream (latest release tag: $new_tag)."
else
    echo "Rebasing $branch onto $upstream ($incoming new upstream commits)..."
    if ! git rebase "$upstream"; then
        echo
        echo "The rebase stopped on a conflict. Fix the listed files, 'git add' them and run"
        echo "'git rebase --continue', or run 'git rebase --abort' to go back to where you were."
        exit 1
    fi
    echo "Done: $branch has $(git rev-list --count "$upstream..HEAD") commit(s) on top of $upstream."
    if [[ "$new_tag" != "$old_tag" ]]; then
        echo "New upstream release tag: $new_tag (previously $old_tag). Rebuild with tools/build-rc.sh --install."
    fi
fi

# A rebase rewrites your commits, so updating the copy on your fork can need a
# force-push; --force-with-lease still refuses if the fork has commits this
# checkout hasn't seen. Never push toward the upstream remote itself.
push_remote=$(git config "branch.$branch.remote" || true)
if [[ -n "$push_remote" && "$push_remote" != "$remote" ]] \
    && [[ "$(git rev-parse HEAD)" != "$(git rev-parse --verify --quiet '@{u}' || true)" ]]; then
    if $push; then
        git push --force-with-lease
    else
        echo "Your fork is behind this branch: git push --force-with-lease (or rerun with --push)."
    fi
fi
