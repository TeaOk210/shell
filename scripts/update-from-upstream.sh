#!/usr/bin/env bash
set -euo pipefail

usage() {
    cat <<'EOF'
Usage: scripts/update-from-upstream.sh [options]

Sync the current branch with the upstream shell repository, rebuild, and
optionally reinstall the local build.

Options:
  --branch <name>      Branch to sync. Defaults to the current branch.
  --build-dir <path>   CMake build directory. Defaults to build.
  --build-script <path>
                       Run this script after syncing instead of cmake.
  --merge              Merge upstream instead of rebasing.
  --no-push            Do not push the updated branch to origin.
  --skip-build         Do not run cmake configure/build.
  --install            Run cmake --install after a successful build.
  --allow-dirty        Do not stop on local uncommitted changes.
  -h, --help           Show this help message.

Environment:
  UPSTREAM_REMOTE      Defaults to "upstream".
  FORK_REMOTE          Defaults to "origin".
EOF
}

script_dir=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
repo_root=$(cd -- "${script_dir}/.." && pwd)

upstream_remote=${UPSTREAM_REMOTE:-upstream}
fork_remote=${FORK_REMOTE:-origin}
branch=$(git -C "${repo_root}" branch --show-current)
build_dir=build
build_script=
sync_mode=rebase
push_after_sync=1
run_build=1
run_install=0
allow_dirty=0

while (($# > 0)); do
    case "$1" in
        --branch)
            branch=${2:?missing value for --branch}
            shift 2
            ;;
        --build-dir)
            build_dir=${2:?missing value for --build-dir}
            shift 2
            ;;
        --build-script)
            build_script=${2:?missing value for --build-script}
            shift 2
            ;;
        --merge)
            sync_mode=merge
            shift
            ;;
        --no-push)
            push_after_sync=0
            shift
            ;;
        --skip-build)
            run_build=0
            shift
            ;;
        --install)
            run_install=1
            shift
            ;;
        --allow-dirty)
            allow_dirty=1
            shift
            ;;
        -h|--help)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage >&2
            exit 1
            ;;
    esac
done

cd "${repo_root}"

git rev-parse --is-inside-work-tree >/dev/null
git remote get-url "${upstream_remote}" >/dev/null
git remote get-url "${fork_remote}" >/dev/null

if [[ -z "${branch}" ]]; then
    echo "Could not determine the current branch. Use --branch <name>." >&2
    exit 1
fi

if (( allow_dirty == 0 )) && [[ -n "$(git status --porcelain)" ]]; then
    echo "Working tree is dirty. Commit or stash changes first, or use --allow-dirty." >&2
    exit 1
fi

echo "Fetching ${upstream_remote}/${branch}..."
git fetch "${upstream_remote}" "${branch}"

if [[ "${sync_mode}" == "rebase" ]]; then
    echo "Rebasing ${branch} onto ${upstream_remote}/${branch}..."
    git rebase "${upstream_remote}/${branch}"
else
    echo "Merging ${upstream_remote}/${branch} into ${branch}..."
    git merge "${upstream_remote}/${branch}"
fi

if (( push_after_sync == 1 )); then
    if [[ "${sync_mode}" == "rebase" ]]; then
        echo "Pushing ${branch} to ${fork_remote} with --force-with-lease..."
        git push --force-with-lease "${fork_remote}" "${branch}"
    else
        echo "Pushing ${branch} to ${fork_remote}..."
        git push "${fork_remote}" "${branch}"
    fi
fi

if (( run_build == 1 )); then
    if [[ -n "${build_script}" ]]; then
        echo "Running custom build script: ${build_script}"
        "${build_script}"
    else
        echo "Configuring CMake in ${build_dir}..."
        cmake -B "${build_dir}" -G Ninja -DCMAKE_BUILD_TYPE=Release

        echo "Building..."
        cmake --build "${build_dir}"
    fi
fi

if (( run_install == 1 )) && [[ -z "${build_script}" ]]; then
    echo "Installing..."
    cmake --install "${build_dir}"
fi

echo "Done."
