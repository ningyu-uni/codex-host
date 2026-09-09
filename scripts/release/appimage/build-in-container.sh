#!/bin/bash
# Assemble the codexhost Linux AppImage. Runs inside the Debian 10 build image
# (see Dockerfile) so every native artefact carries the glibc 2.28 baseline of
# the oldest supported distribution.
set -euo pipefail

source_root="${1:-/src}"
output_root="${2:-/out}"
cd "$source_root"

architecture="$(uname -m)"
case "$architecture" in
  x86_64) rust_target="x86_64-unknown-linux-gnu" ;;
  aarch64) rust_target="aarch64-unknown-linux-gnu" ;;
  *) echo "unsupported AppImage architecture: $architecture" >&2; exit 1 ;;
esac
version="$(node -p "require('./package.json').version")"
app_directory="$source_root/build/appimage/codexhost.AppDir"

echo "==> building codexhost ${version} for ${rust_target}"
npm ci
npm run build:typescript
npm run build:renderer
cargo build --release --locked --target "$rust_target" \
  --package codexhost-launcher \
  --package codexhost-platform \
  --package codexhost-shim \
  --package codexhost-updater
# Only the installation module can be gated here. The desktop_launch, process,
# and process_supervision tests drive real pidfd signalling and assume a merged
# /usr, neither of which a build container provides, so they fail on the
# environment rather than on the code.
cargo test --release --locked --target "$rust_target" \
  --package codexhost-platform --lib linux_installation::

echo "==> assembling AppDir"
rm -rf "$app_directory"
mkdir -p "$app_directory/usr/bin" "$app_directory/usr/libexec" "$app_directory/usr/app"

rust_output="target/${rust_target}/release"
install -m 0755 "$rust_output/codexhost" "$app_directory/usr/bin/codexhost"
install -m 0755 "$rust_output/codexhost-shim" "$app_directory/usr/libexec/codexhost-shim"
install -m 0755 "$rust_output/codexhost-updater" "$app_directory/usr/libexec/codexhost-updater"

node packages/host-runtime/scripts/build-release.mjs \
  --output "$app_directory/usr/app/host-runtime.mjs"
node packages/desktop-control/scripts/build-release.mjs \
  --output "$app_directory/usr/app/desktop-controller.mjs"
install -m 0644 packages/renderer-extension/dist/production.js \
  "$app_directory/usr/app/renderer-extension.js"

cp -a /opt/node "$app_directory/usr/node"
rm -rf "$app_directory/usr/node/lib/node_modules" \
       "$app_directory/usr/node/include" \
       "$app_directory/usr/node/share"
find "$app_directory/usr/node/bin" -mindepth 1 ! -name node -delete

sed "s|@VERSION@|${version}|" scripts/release/appimage/AppRun > "$app_directory/AppRun"
chmod 0755 "$app_directory/AppRun"
install -m 0644 scripts/release/appimage/codexhost.desktop "$app_directory/codexhost.desktop"
install -m 0644 packages/renderer-extension/src/assets/codexhost-icon.png \
  "$app_directory/codexhost.png"

echo "==> verifying the glibc 2.28 baseline"
node --input-type=module -e "
import { verifyLinuxGlibcBaseline } from './scripts/release/linux-glibc.mjs';
const verified = verifyLinuxGlibcBaseline({
  packageRoot: process.argv[1],
  baseline: '2.28',
});
for (const { relative, maximum } of verified) console.log(\`  \${relative}: GLIBC_\${maximum}\`);
" "$app_directory/usr"
ldd_output="$(objdump -T "$app_directory/usr/node/bin/node" | grep -o 'GLIBC_[0-9.]*' | sort -Vu | tail -1)"
echo "  usr/node/bin/node: ${ldd_output}"

echo "==> packaging AppImage"
mkdir -p "$output_root"
APPIMAGE_EXTRACT_AND_RUN=1 ARCH="$architecture" appimagetool \
  "$app_directory" "$output_root/codexhost-${version}-${architecture}.AppImage"
ls -lh "$output_root"
