#!/bin/bash

set -eu
launcher_path=$(readlink -f "$0")
source "${launcher_path%/*}/scripts/manage.sh"
cd -- "$project_dir"

xpra_app=$(find_xpra) || fail "Run bash \"$project_dir/scripts/manage.sh\" install first."
ensure_docker
ensure_xpra_password
mkdir -p -- Shared
# The desktop must rejoin the gateway's network when Compose refreshes the password.
compose stop desktop
compose up -d --force-recreate --wait --wait-timeout 90

# macOS uses a 2x backing surface. Xpra maps it to window coordinates in points.
open -n -a "$xpra_app" --args attach tcp://127.0.0.1:14500/ \
    --challenge-handlers="file:filename=$xpra_password_file" \
    --opengl=auto \
    --desktop-scaling=0.5 \
    --dpi=96 \
    --min-quality=95 \
    --video-scaling=0 \
    --clipboard=yes \
    --clipboard-direction=both \
    --local-clipboard=CLIPBOARD \
    --remote-clipboard=CLIPBOARD \
    --swap-keys=yes
