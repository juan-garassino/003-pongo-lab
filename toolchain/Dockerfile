FROM debian:bullseye-slim@sha256:e5b6442dd2e9684cf5e87d8338b5968f3b348636fc0be6d7850a381e3731a2bd

# Bullseye's final security packages have moved to the signed archive.
RUN sed -i 's|http://deb.debian.org/debian-security|http://archive.debian.org/debian-security|' /etc/apt/sources.list \
    && printf 'Acquire::Check-Valid-Until "false";\n' > /etc/apt/apt.conf.d/99archive

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates curl clang llvm make gcc xxd bsdextrautils \
    libxml2 libssl1.1 libuuid1 libblocksruntime0 \
    && rm -rf /var/lib/apt/lists/*

# Use the upstream Mach-O tools with their original runtime libraries.
# Check the downloads against the SHA-256 values from the upstream index.
RUN cd /tmp \
    && curl -fsSLO https://assets.checkra.in/debian/ld64_954.16-0_amd64.deb \
    && curl -fsSLO https://assets.checkra.in/debian/cctools-strip_949.0.1-2_amd64.deb \
    && echo '18de17bb246a02c4b407cba609fbc24effb354dcc1cc3e8397802287b1049b82  ld64_954.16-0_amd64.deb' | sha256sum -c - \
    && echo '8d0e99921de851faefcb1fc867ada0a2348605f3f279e24131b5a424df9fa700  cctools-strip_949.0.1-2_amd64.deb' | sha256sum -c - \
    && apt-get update \
    && apt-get install -y ./ld64_954.16-0_amd64.deb ./cctools-strip_949.0.1-2_amd64.deb \
    && rm -rf /var/lib/apt/lists/* /tmp/*.deb

# ld64 loads libLTO.so dynamically for PongoOS's -flto objects.
RUN apt-get update && apt-get install -y --no-install-recommends llvm-11-dev \
    && rm -rf /var/lib/apt/lists/*

ENV LD_LIBRARY_PATH=/usr/lib/llvm-11/lib
ENV EMBEDDED_LDFLAGS="-fuse-ld=/usr/bin/ld64 -Wl,-lto_library,/usr/lib/llvm-11/lib/libLTO.so"
WORKDIR /work
CMD ["bash", "scripts/build.sh"]
