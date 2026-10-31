#!/usr/bin/env bash
# Releases MeetingRush X.Y.Z, one step per run;
# run it again after merging each pull request it opens:
# 1. opens a pull request setting VERSION,
# 2. tags main and waits for the release workflow,
# 3. opens a tap pull request pointing the cask at the new zip,
# 4. audits the merged cask.
# Env: TAP_REPO, the homebrew-tap clone (default: homebrew-tap next to this repository).
set -euo pipefail

cd "$(dirname "$0")/.."

TARGET="${1:-}"
if [[ ! "$TARGET" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
    echo "Usage: make release VERSION=X.Y.Z" >&2
    exit 1
fi
TAG="v$TARGET"
SLUG="${TARGET//./-}"
CASK="Casks/meetingrush.rb"
ZIP="MeetingRush-$TARGET.zip"

die() {
    echo "$*" >&2
    exit 1
}

# Prints -1, 0 or 1 as X.Y.Z $1 is lower than, equal to or higher than $2.
compare_versions() {
    local a b i
    IFS=. read -r -a a <<< "$1"
    IFS=. read -r -a b <<< "$2"
    for i in 0 1 2; do
        if (( 10#${a[i]} != 10#${b[i]} )); then
            (( 10#${a[i]} < 10#${b[i]} )) && echo -1 || echo 1
            return
        fi
    done
    echo 0
}

# The directory for a new worktree of repository $1: inside it for a bare repository, else next to it.
worktree_dir() {
    local common
    common="$(git -C "$1" rev-parse --path-format=absolute --git-common-dir)"
    if [[ "$(git -C "$common" rev-parse --is-bare-repository)" == true ]]; then
        echo "$common/$2"
    else
        echo "$(dirname "$(dirname "$common")")/$2"
    fi
}

# Adds a worktree on a new branch $3 from origin/main of repository $1 at $2, or reuses one already there.
add_worktree() {
    if [[ -d "$2" ]]; then
        [[ "$(git -C "$2" branch --show-current)" == "$3" ]] || die "$2 exists but isn't on branch $3"
        [[ -z "$(git -C "$2" status --porcelain)" ]] || die "$2 has uncommitted changes"
    else
        git -C "$1" worktree add -q "$2" -b "$3" origin/main
    fi
}

# Succeeds when origin of repository $1 has ref $2; dies on network or auth errors rather than reading them as absent.
remote_has() {
    local status=0
    git -C "$1" ls-remote --exit-code origin "$2" > /dev/null || status=$?
    case "$status" in
        0) return 0 ;;
        2) return 1 ;;
        *) die "Couldn't reach origin of $1" ;;
    esac
}

# Commits path $2 in worktree $1 with message $3, unless an earlier run already did.
commit_once() {
    if [[ -z "$(git -C "$1" rev-list origin/main..HEAD)" ]]; then
        git -C "$1" add "$2"
        git -C "$1" commit -q -m "$3"
    fi
}

github_repo() {
    gh repo view "$(git -C "$1" remote get-url origin)" --json nameWithOwner -q .nameWithOwner
}

cask_version() {
    sed -nE 's/^  version "(.*)"$/\1/p'
}

# Succeeds when release $TAG exists and has the zip; reads the list whole, as grep -q could cut gh off mid-pipe.
release_has_zip() {
    local assets
    assets="$(gh release view "$TAG" --repo "$REPO" --json assets -q '.assets[].name' 2>/dev/null)" || return 1
    grep -qxF "$ZIP" <<< "$assets"
}

gh auth status > /dev/null 2>&1 || die "gh isn't logged in; run gh auth login"

COMMON="$(git rev-parse --path-format=absolute --git-common-dir)"
if [[ "$(git -C "$COMMON" rev-parse --is-bare-repository)" == true ]]; then
    DEFAULT_TAP="$(dirname "$COMMON")/homebrew-tap"
else
    DEFAULT_TAP="$(dirname "$(git rev-parse --show-toplevel)")/homebrew-tap"
fi
TAP_REPO="${TAP_REPO:-$DEFAULT_TAP}"
git -C "$TAP_REPO" rev-parse --git-dir > /dev/null 2>&1 || die "No homebrew-tap clone at $TAP_REPO; set TAP_REPO"

REPO="$(github_repo .)"
TAP="$(github_repo "$TAP_REPO")"
TAP_NAME="${TAP%%/*}/$(basename "$TAP" | sed 's/^homebrew-//')"

# Forced for release tags, so one deleted and re-created on origin replaces a stale local copy.
git fetch -q origin "+refs/tags/v*:refs/tags/v*"
git fetch -q origin
git -C "$TAP_REPO" fetch -q origin

CURRENT="$(git show origin/main:VERSION | tr -d '[:space:]')"
case "$(compare_versions "$TARGET" "$CURRENT")" in
    -1) die "$TARGET is older than $CURRENT on main" ;;
    1)
        # Step 1: a pull request setting VERSION.
        BRANCH="release-$SLUG"
        PR="$(gh pr list --repo "$REPO" --head "$BRANCH" --state open --json url -q '.[0].url')"
        if [[ -z "$PR" ]]; then
            DIR="$(worktree_dir . "$BRANCH")"
            # A branch already on origin is from an earlier run that stopped before opening the pull request.
            if ! remote_has . "refs/heads/$BRANCH"; then
                add_worktree . "$DIR" "$BRANCH"
                echo "$TARGET" > "$DIR/VERSION"
                commit_once "$DIR" VERSION "Release $TARGET"
                git -C "$DIR" push -q -u origin "$BRANCH"
            fi
            PR="$(gh pr create --repo "$REPO" --base main --head "$BRANCH" \
                --title "Release $TARGET" --body "Sets VERSION to $TARGET, so the $TAG tag can be released.")"
        fi
        echo "Version pull request: $PR"
        echo "Merge it, then run make release VERSION=$TARGET again."
        exit 0
        ;;
esac

TAP_VERSION="$(git -C "$TAP_REPO" show "origin/main:$CASK" | cask_version)"
if [[ "$TAP_VERSION" == "$TARGET" ]]; then
    # Step 4: audit the merged cask. brew audit only reads the installed tap, not a file or worktree.
    INSTALLED="$(brew --repo "$TAP_NAME")/$CASK"
    [[ -f "$INSTALLED" ]] || die "The $TAP_NAME tap isn't installed; run brew tap $TAP_NAME"
    if [[ "$(cask_version < "$INSTALLED")" == "$TARGET" ]]; then
        brew audit --cask --strict --online "$TAP_NAME/meetingrush"
        echo "MeetingRush $TARGET is released; brew upgrade --cask meetingrush installs it."
    else
        echo "The tap has MeetingRush $TARGET; run brew update, then make release VERSION=$TARGET again to audit it."
    fi
    exit 0
fi

TAP_BRANCH="meetingrush-$SLUG"
TAP_PR="$(gh pr list --repo "$TAP" --head "$TAP_BRANCH" --state open --json url -q '.[0].url')"
if [[ -n "$TAP_PR" ]]; then
    echo "Tap pull request: $TAP_PR"
    echo "Merge it, then run make release VERSION=$TARGET again."
    exit 0
fi

if ! release_has_zip; then
    # Step 2: tag main and wait for the release workflow.
    if ! remote_has . "refs/tags/$TAG"; then
        if git rev-parse -q --verify "refs/tags/$TAG" > /dev/null; then
            [[ "$(git rev-parse "$TAG^{commit}")" == "$(git rev-parse origin/main)" ]] ||
                die "Local tag $TAG isn't on origin/main; delete it with git tag -d $TAG"
        else
            git tag -a "$TAG" -m "MeetingRush $TARGET" origin/main
        fi
        git push -q origin "refs/tags/$TAG"
        echo "Pushed $TAG."
    fi

    # Matched on the tagged commit too, so a re-created tag doesn't pick up the old tag's failed run.
    TAG_SHA="$(git rev-parse "$TAG^{commit}")"
    RUN=""
    for _ in $(seq 30); do
        RUN="$(gh run list --repo "$REPO" --workflow release.yml --branch "$TAG" --commit "$TAG_SHA" --limit 1 \
            --json databaseId -q '.[0].databaseId')"
        [[ -n "$RUN" ]] && break
        sleep 2
    done
    [[ -n "$RUN" ]] || die "No release workflow run found for $TAG"
    gh run watch "$RUN" --repo "$REPO" --compact --exit-status ||
        die "The release workflow failed: $(gh run view "$RUN" --repo "$REPO" --json url -q .url)"
    release_has_zip ||
        die "The release workflow finished but release $TAG has no $ZIP"
fi

# Step 3: a tap pull request pointing the cask at the new zip.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
gh release download "$TAG" --repo "$REPO" --pattern "$ZIP" --dir "$TMP"
gh attestation verify "$TMP/$ZIP" --repo "$REPO" --signer-workflow "$REPO/.github/workflows/release.yml" \
    --source-ref "refs/tags/$TAG" --deny-self-hosted-runners > /dev/null ||
    die "$ZIP failed its provenance attestation"
SHA256="$(shasum -a 256 "$TMP/$ZIP" | cut -d' ' -f1)"

TAP_DIR="$(worktree_dir "$TAP_REPO" "$TAP_BRANCH")"
if ! remote_has "$TAP_REPO" "refs/heads/$TAP_BRANCH"; then
    add_worktree "$TAP_REPO" "$TAP_DIR" "$TAP_BRANCH"
    sed -i '' -E \
        -e "s/^  version \".*\"$/  version \"$TARGET\"/" \
        -e "s/^  sha256 \".*\"$/  sha256 \"$SHA256\"/" \
        "$TAP_DIR/$CASK"
    grep -qxF "  sha256 \"$SHA256\"" "$TAP_DIR/$CASK" && [[ "$(cask_version < "$TAP_DIR/$CASK")" == "$TARGET" ]] ||
        die "Couldn't update version and sha256 in $TAP_DIR/$CASK"
    # Reverted on failure, so the next run doesn't stop at the dirty worktree.
    brew style "$TAP_DIR/$CASK" || {
        git -C "$TAP_DIR" checkout -q -- "$CASK"
        die "brew style rejected the updated cask"
    }
    commit_once "$TAP_DIR" "$CASK" "Update MeetingRush to $TARGET"
    git -C "$TAP_DIR" push -q -u origin "$TAP_BRANCH"
fi
TAP_PR="$(gh pr create --repo "$TAP" --base main --head "$TAP_BRANCH" \
    --title "Update MeetingRush to $TARGET" \
    --body "Points the cask at the $TAG release, whose zip passed gh attestation verify.")"
echo "Tap pull request: $TAP_PR"
echo "Merge it, then run brew update and make release VERSION=$TARGET again to audit it."
