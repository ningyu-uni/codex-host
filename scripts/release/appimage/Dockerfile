# syntax=docker/dockerfile:1
#
# Debian 10 (buster) build image for the codexhost Linux AppImage. Buster ships
# glibc 2.28, so everything compiled here loads on the oldest distribution the
# AppImage targets. Node.js 24 and Electron both require glibc >= 2.28, which
# makes buster the floor rather than an arbitrary choice.
FROM debian:10 AS build

ARG NODE_VERSION=24.13.1
ARG RUST_VERSION=1.97.1
# archive.debian.org serves buster at roughly 100 KB/s, which makes this layer
# take hours. Any mirror carrying the Debian archive works; override with
# --build-arg APT_MIRROR=http://archive.debian.org when none is reachable.
# It must be plain http: the base image ships no ca-certificates yet.
ARG APT_MIRROR=http://mirror.nju.edu.cn/debian-archive

# Buster left the live mirrors and its archived Release file is expired.
RUN printf '%s\n' \
      "deb ${APT_MIRROR}/debian buster main" \
      "deb ${APT_MIRROR}/debian-security buster/updates main" \
      > /etc/apt/sources.list \
  && printf 'Acquire::Check-Valid-Until "false";\n' \
      > /etc/apt/apt.conf.d/99-archived-buster \
  && apt-get update \
  && apt-get install -y --no-install-recommends \
       build-essential \
       ca-certificates \
       curl \
       desktop-file-utils \
       file \
       xz-utils \
  && rm -rf /var/lib/apt/lists/*

RUN set -eux; \
    architecture="$(uname -m)"; \
    case "$architecture" in \
      x86_64) node_architecture=x64 ;; \
      aarch64) node_architecture=arm64 ;; \
      *) echo "unsupported architecture: $architecture" >&2; exit 1 ;; \
    esac; \
    archive="node-v${NODE_VERSION}-linux-${node_architecture}.tar.xz"; \
    curl -fsSLO --retry 5 --retry-delay 2 "https://nodejs.org/dist/v${NODE_VERSION}/${archive}"; \
    curl -fsSLO --retry 5 --retry-delay 2 "https://nodejs.org/dist/v${NODE_VERSION}/SHASUMS256.txt"; \
    grep " ${archive}\$" SHASUMS256.txt | sha256sum -c -; \
    mkdir -p /opt/node; \
    tar -xJf "${archive}" -C /opt/node --strip-components=1; \
    rm "${archive}" SHASUMS256.txt
ENV PATH=/opt/node/bin:$PATH

# static.rust-lang.org serves the toolchain tarballs at under 10 KB/s here, so
# the download stalls out. rustup still verifies the channel manifest hashes and
# cargo still verifies Cargo.lock checksums, so a mirror stays byte-verified.
# Pass --build-arg RUST_MIRROR= to fall back to the official servers.
ARG RUST_MIRROR=https://rsproxy.cn
RUN set -eux; \
    if [ -n "${RUST_MIRROR}" ]; then \
      export RUSTUP_DIST_SERVER="${RUST_MIRROR}"; \
      export RUSTUP_UPDATE_ROOT="${RUST_MIRROR}/rustup"; \
    fi; \
    curl -fsSL --retry 5 --retry-delay 2 https://sh.rustup.rs -o /tmp/rustup-init.sh; \
    sh /tmp/rustup-init.sh -y --no-modify-path --profile minimal \
      --default-toolchain "${RUST_VERSION}" --component clippy,rustfmt; \
    rm /tmp/rustup-init.sh
ENV PATH=/root/.cargo/bin:$PATH

RUN set -eux; \
    if [ -n "${RUST_MIRROR}" ]; then \
      printf '%s\n' \
        '[source.crates-io]' \
        'replace-with = "mirror"' \
        '[source.mirror]' \
        "registry = \"sparse+${RUST_MIRROR}/index/\"" \
        > /root/.cargo/config.toml; \
    fi

# appimagetool needs FUSE to mount itself, which a container does not have;
# APPIMAGE_EXTRACT_AND_RUN makes it unpack to a temporary directory instead.
RUN set -eux; \
    architecture="$(uname -m)"; \
    curl -fsSL --retry 5 --retry-delay 2 -o /usr/local/bin/appimagetool \
      "https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-${architecture}.AppImage"; \
    chmod 0755 /usr/local/bin/appimagetool
ENV APPIMAGE_EXTRACT_AND_RUN=1

WORKDIR /src
COPY . /src
RUN scripts/release/appimage/build-in-container.sh /src /out

FROM scratch AS export
COPY --from=build /out/ /
