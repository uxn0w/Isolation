#!/bin/bash

set -eu
script_path=$(readlink -f "${BASH_SOURCE[0]}")
script_dir=${script_path%/*}
project_dir=${script_dir%/*}
export PATH="$HOME/.docker/bin:/Applications/Docker.app/Contents/Resources/bin:/usr/local/bin:/opt/homebrew/bin:$PATH"

managed_dir="$project_dir/.local"
managed_xpra="$managed_dir/Xpra.app"
xpra_password_file="$managed_dir/xpra-password"

fail() {
    printf '%s\n' "$*" >&2
    exit 1
}

compose() {
    docker --context desktop-linux compose --project-name app-isolation --file "$project_dir/compose.yaml" "$@"
}

ensure_docker() {
    command -v docker >/dev/null || fail 'Install Docker Desktop for Mac.'
    docker compose version >/dev/null 2>&1 || fail 'Update Docker Desktop to a version that includes Docker Compose.'
    if ! docker --context desktop-linux info >/dev/null 2>&1; then
        printf '%s\n' 'Starting Docker Desktop…'
        docker desktop start --timeout 90 || fail 'Docker Desktop failed to start. Open it and check its settings.'
        docker --context desktop-linux info >/dev/null || fail 'The Docker Desktop context is unavailable.'
    fi
}

find_xpra() {
    local app
    for app in "$managed_xpra" "$HOME/Applications/Xpra.app" /Applications/Xpra.app; do
        if [[ -x "$app/Contents/MacOS/Xpra" ]]; then
            printf '%s\n' "$app"
            return 0
        fi
    done
    return 1
}

ensure_xpra_password() (
    umask 077
    set -o pipefail
    mkdir -p -- "$managed_dir"
    if [[ -L $xpra_password_file || ( -e $xpra_password_file && ! -f $xpra_password_file ) ]]; then
        fail 'The Xpra password path must be a regular file.'
    fi
    if [[ ! -s $xpra_password_file ]]; then
        [[ ! -e $xpra_password_file ]] || fail 'The Xpra password file is empty. Remove it and try again.'
        local pending_password
        pending_password=$(mktemp "$managed_dir/.xpra-password.XXXXXXXX")
        trap 'rm -f -- "$pending_password"' EXIT
        openssl rand -hex 32 | tr -d '\n' > "$pending_password"
        mv -n -- "$pending_password" "$xpra_password_file"
    fi
    chmod 600 "$xpra_password_file"
)

install_xpra() (
    if find_xpra >/dev/null; then
        printf '%s\n' 'Xpra is already installed.'
        return 0
    fi

    arch=$(uname -m)
    case "$arch" in
        arm64|x86_64) ;;
        *) fail "Unsupported architecture: $arch." ;;
    esac

    mkdir -p -- "$managed_dir"
    staging=$(mktemp -d "$managed_dir/.xpra.XXXXXXXX")
    mount_point="$staging/mount"
    trap 'if [[ -z ${mounted:-} ]] || hdiutil detach "$mount_point" >/dev/null; then rm -rf -- "$staging"; fi' EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM

    version=7.0-r0
    url="https://xpra.org/stable/MacOS/$arch/Xpra-$arch-$version.dmg"
    printf '%s\n' 'Downloading Xpra for Mac…'
    curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --retry 3 \
        --output "$staging/Xpra.dmg" "$url"
    mkdir -- "$mount_point"
    hdiutil attach -readonly -nobrowse -mountpoint "$mount_point" "$staging/Xpra.dmg" >/dev/null
    mounted=1

    codesign --verify --deep --strict \
        -R='identifier "org.xpra.xpra" and anchor apple generic and certificate leaf[subject.OU] = "YP7MH6R5DZ"' \
        "$mount_point/Xpra.app"
    spctl --assess --type execute "$mount_point/Xpra.app"
    ditto "$mount_point/Xpra.app" "$staging/Xpra.app"
    mv -n -- "$staging/Xpra.app" "$managed_dir/"
)

install_container() (
    local timezone=${1:-${DOCKER_GUI_TZ:-}}
    local locale=${2:-${DOCKER_GUI_LANG:-}}
    (( $# <= 2 )) || fail 'Pass at most two arguments to ./scripts/manage.sh install [TZ] [LANG].'

    if [[ -n $timezone ]]; then
        [[ $timezone =~ ^([[:alnum:]_+-]+/)*[[:alnum:]_+-]+$ && -f /usr/share/zoneinfo/$timezone ]] ||
            fail "Unknown time zone $timezone. Use a time zone such as Europe/Moscow."
    fi
    if [[ -n $locale ]]; then
        [[ $locale =~ ^(C|[[:alpha:]]{2,3}_[[:alnum:]]{2,3})\.UTF-8$ ]] ||
            fail "Invalid locale format for $locale. Use en_US.UTF-8 or ru_RU.UTF-8."
    fi

    ensure_docker
    install_xpra
    ensure_xpra_password
    mkdir -p -- Shared

    local existing_env=/dev/null
    [[ ! -f .env ]] || existing_env=.env
    local pending_env
    pending_env=$(mktemp .env.XXXXXXXX)
    trap 'rm -f -- "$pending_env"' EXIT
    awk -v tz="$timezone" -v lang="$locale" '
        /^[[:space:]]*(export[[:space:]]+)?DOCKER_GUI_TZ[[:space:]]*([:=]|$)/ {
            has_tz = 1
            if (tz != "") next
        }
        /^[[:space:]]*(export[[:space:]]+)?DOCKER_GUI_LANG[[:space:]]*([:=]|$)/ {
            has_lang = 1
            if (lang != "") next
        }
        /^[[:space:]]*(export[[:space:]]+)?DOCKER_GUI_SSH_(HOST|PORT|USER|PASSWORD|HOST_KEY)[[:space:]]*([:=]|$)/ {
            key = $0
            sub(/^[[:space:]]*(export[[:space:]]+)?/, "", key)
            sub(/[[:space:]:=].*$/, "", key)
            seen[key] = 1
        }
        { print }
        END {
            if (tz != "" || !has_tz) print "DOCKER_GUI_TZ=" (tz != "" ? tz : "UTC")
            if (lang != "" || !has_lang) print "DOCKER_GUI_LANG=" (lang != "" ? lang : "en_US.UTF-8")
            if (!seen["DOCKER_GUI_SSH_HOST"]) print "DOCKER_GUI_SSH_HOST="
            if (!seen["DOCKER_GUI_SSH_PORT"]) print "DOCKER_GUI_SSH_PORT=22"
            if (!seen["DOCKER_GUI_SSH_USER"]) print "DOCKER_GUI_SSH_USER="
            if (!seen["DOCKER_GUI_SSH_PASSWORD"]) print "DOCKER_GUI_SSH_PASSWORD="
            if (!seen["DOCKER_GUI_SSH_HOST_KEY"]) print "DOCKER_GUI_SSH_HOST_KEY="
        }
    ' "$existing_env" > "$pending_env"

    unset DOCKER_GUI_TZ DOCKER_GUI_LANG
    compose --env-file "$pending_env" build
    cmp -s "$pending_env" .env || mv -f -- "$pending_env" .env
    chmod 600 .env
)

uninstall_container() {
    (( $# == 0 )) || fail 'Usage: ./scripts/manage.sh uninstall'
    [[ ! -L $managed_dir ]] || fail 'The managed Xpra directory must not be a symbolic link.'

    ensure_docker
    compose down --remove-orphans --volumes --rmi local --timeout 30
    rm -rf -- "$managed_xpra"
    rm -f -- "$xpra_password_file" "$project_dir/.env"
    rmdir "$managed_dir" 2>/dev/null || true
    printf '%s\n' 'Removed Isolation, its app profiles, saved SSH host keys, and .env. Shared is still available.'
}

if [[ ${BASH_SOURCE[0]} == "$0" ]]; then
    cd -- "$project_dir"

    case "${1:---help}" in
        install)
            shift
            install_container "$@"
            printf '%s\n' 'Installation complete. Open run.command to start Isolation.'
            ;;
        uninstall)
            shift
            uninstall_container "$@"
            ;;
        -h|--help)
            printf '%s\n' './scripts/manage.sh install [TZ] [LANG]' './scripts/manage.sh uninstall' \
                '  uninstall also removes .env, app profiles, and saved SSH host keys. Shared is kept.'
            ;;
        *)
            printf '%s\n' 'Specify install or uninstall.' >&2
            exit 2
            ;;
    esac
fi
