#!/bin/bash
# Build the codexhost Linux AppImage in a Debian 10 container and copy the
# result into build/appimage/ on the host.
#
#   scripts/release/appimage/build.sh [--platform linux/amd64]
set -euo pipefail

platform="linux/amd64"
apt_mirror=""
rust_mirror=""
rust_mirror_set=0
while [ "$#" -gt 0 ]; do
  case "$1" in
    --platform) platform="$2"; shift 2 ;;
    --platform=*) platform="${1#--platform=}"; shift ;;
    --apt-mirror) apt_mirror="$2"; shift 2 ;;
    --apt-mirror=*) apt_mirror="${1#--apt-mirror=}"; shift ;;
    --rust-mirror) rust_mirror="$2"; rust_mirror_set=1; shift 2 ;;
    --rust-mirror=*) rust_mirror="${1#--rust-mirror=}"; rust_mirror_set=1; shift ;;
    *)
      echo "usage: $0 [--platform PLATFORM] [--apt-mirror URL] [--rust-mirror URL]" >&2
      exit 1
      ;;
  esac
done

repository_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$repository_root"

build_arguments=()
if [ -n "$apt_mirror" ]; then
  build_arguments+=(--build-arg "APT_MIRROR=${apt_mirror}")
fi
# An explicitly empty --rust-mirror selects the official Rust servers.
if [ "$rust_mirror_set" -eq 1 ]; then
  build_arguments+=(--build-arg "RUST_MIRROR=${rust_mirror}")
fi

DOCKER_BUILDKIT=1 docker build \
  --platform "$platform" \
  "${build_arguments[@]+"${build_arguments[@]}"}" \
  --file scripts/release/appimage/Dockerfile \
  --target export \
  --output "type=local,dest=build/appimage" \
  .
ls -lh build/appimage
