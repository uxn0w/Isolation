FROM debian:trixie-slim AS ssh-proxy

RUN apt-get -o Acquire::Retries=3 update \
    && apt-get -o Acquire::Retries=3 install -y --no-install-recommends \
        busybox ca-certificates dnscrypt-proxy nftables openssh-client redsocks sshpass \
    && rm -rf /var/lib/apt/lists/* \
    && useradd --uid 1001 --create-home ssh-proxy \
    && install -d -o ssh-proxy -g ssh-proxy -m 0700 /var/lib/ssh-proxy \
    && install -o ssh-proxy -g ssh-proxy -m 0600 /dev/null /var/lib/ssh-proxy/known_hosts

COPY --chmod=755 scripts/private/start-ssh-proxy.sh /usr/local/bin/start-ssh-proxy
COPY --chmod=755 scripts/private/check-ssh-gateway.sh /usr/local/bin/check-ssh-gateway
COPY configs/gateway/firewall.nft configs/gateway/redsocks.conf configs/gateway/dnscrypt-proxy.toml /etc/app-isolation/
ENTRYPOINT ["/usr/local/bin/start-ssh-proxy"]

FROM debian:bookworm-slim AS desktop

RUN apt-get -o Acquire::Retries=3 update \
    && apt-get -o Acquire::Retries=3 install -y --no-install-recommends ca-certificates curl \
    && rm -rf /var/lib/apt/lists/*

RUN sed -i \
        -e 's|http://deb.debian.org/debian-security|https://security.debian.org/debian-security|' \
        -e 's|http://deb.debian.org/debian|https://ftp.debian.org/debian|' \
        /etc/apt/sources.list.d/debian.sources \
    && printf '%s\n' 'Acquire::Retries "4";' 'Acquire::https::Timeout "20";' > /etc/apt/apt.conf.d/80-retries \
    && curl -fsSL https://xpra.org/xpra.asc -o /usr/share/keyrings/xpra.asc \
    && curl -fsSL https://packages.microsoft.com/keys/microsoft.asc -o /usr/share/keyrings/microsoft.asc \
    && printf '%s\n' 'deb [signed-by=/usr/share/keyrings/xpra.asc] https://xpra.org bookworm main' \
        > /etc/apt/sources.list.d/xpra.list \
    && printf '%s\n' 'deb [signed-by=/usr/share/keyrings/microsoft.asc] https://packages.microsoft.com/repos/code stable main' \
        > /etc/apt/sources.list.d/vscode.list

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    rm -f /etc/apt/apt.conf.d/docker-clean \
    && apt-get update \
    && apt-get install -y --no-install-recommends \
        dbus-x11 fonts-dejavu-core fonts-liberation git \
        pulseaudio xauth xfonts-base xpra-audio-server xpra-client xpra-codecs xpra-server xpra-x11 xvfb \
    && rm -rf /var/lib/apt/lists/*

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    apt-get update \
    && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends locales tzdata \
    && rm -rf /var/lib/apt/lists/*

RUN --mount=type=bind,source=configs/apps.list,target=/tmp/apps.list \
    --mount=type=cache,target=/var/cache/apt,sharing=locked <<'SH'
set -eu
packages=$(awk '
    { sub(/#.*/, ""); sub(/\r$/, "") }
    NF == 0 { next }
    NF != 1 || $1 !~ /^[a-z0-9][a-z0-9+.-]+$/ {
        printf "Invalid Debian package name in configs/apps.list at line %d. Use one package name per line.\n", NR > "/dev/stderr"
        exit 1
    }
    { print $1 }
' /tmp/apps.list)

if [ -n "$packages" ]; then
    set -f
    set -- $packages
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends --no-remove "$@"
    rm -rf /var/lib/apt/lists/*
fi
SH

ARG DOCKER_GUI_LANG=en_US.UTF-8
RUN if [ "$DOCKER_GUI_LANG" != C.UTF-8 ]; then \
        localedef -i "${DOCKER_GUI_LANG%.UTF-8}" -f UTF-8 "$DOCKER_GUI_LANG"; \
    fi

RUN useradd --create-home --shell /bin/bash desktop \
    && install -d -o desktop -g desktop -m 0700 /run/user/1000 \
    && install -d -o desktop -g desktop /usr/lib/firefox-esr/distribution \
    && install -d /workspace /usr/local/share/app-isolation

COPY configs/firefox-policies.json /usr/local/share/app-isolation/firefox-policies.json
COPY --chmod=755 scripts/private/start-session.sh /usr/local/bin/start-session

ENV XDG_RUNTIME_DIR=/run/user/1000
USER desktop
WORKDIR /workspace
ENTRYPOINT ["dbus-run-session", "--", "/usr/local/bin/start-session"]
