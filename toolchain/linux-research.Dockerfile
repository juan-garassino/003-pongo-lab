FROM debian:trixie-slim@sha256:7378260c0a098d27ac206225db5e7d92b8c7c84ea7afccc86eeb513756bbd392

RUN dpkg --add-architecture arm64 \
    && printf 'deb http://deb.debian.org/debian trixie main\ndeb http://deb.debian.org/debian trixie-updates main\ndeb http://security.debian.org/debian-security trixie-security main\n' \
       > /etc/apt/sources.list \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
       7zip bc bison build-essential ca-certificates clang cpio curl \
       device-tree-compiler dmg2img flex gcc-aarch64-linux-gnu git libelf-dev \
       libc6-dev-arm64-cross libssl-dev lld llvm \
       make perl-base python3 xz-utils \
       busybox-static:arm64 \
    && rm -rf /var/lib/apt/lists/*

ARG RUSTUP_VERSION=1.28.2
ARG RUST_VERSION=1.85.1
ENV CARGO_HOME=/opt/cargo RUSTUP_HOME=/opt/rustup
RUN cd /tmp \
    && curl -fsSLO "https://static.rust-lang.org/rustup/archive/${RUSTUP_VERSION}/x86_64-unknown-linux-gnu/rustup-init" \
    && chmod +x rustup-init \
    && ./rustup-init -y --no-modify-path --profile minimal \
       --default-toolchain "${RUST_VERSION}" \
    && rm -rf /tmp/rustup-init \
    && /opt/cargo/bin/rustup target add aarch64-unknown-none-softfloat \
    && chmod -R a+rX /opt/cargo /opt/rustup

ENV PATH=/opt/cargo/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin
WORKDIR /work
