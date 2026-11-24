#!/bin/sh
set -eu

password_file=/run/secrets/xpra_password
if [ ! -r "$password_file" ] || [ ! -s "$password_file" ]; then
    printf '%s\n' 'The Xpra password is missing. Run the installer or run.command on the Mac.' >&2
    exit 1
fi

socks_proxy=${DOCKER_GUI_SOCKS_PROXY:-}
# Xpra scales cursor bitmaps by 0.5 along with the Retina desktop.
code_command='env XCURSOR_SIZE=48 code --disable-setuid-sandbox --force-device-scale-factor=2 --wait --new-window /workspace'
if [ -n "$socks_proxy" ]; then
    code_command="$code_command --proxy-server=socks5://$socks_proxy"
fi

python3 - "$socks_proxy" <<'PY'
import json
import sys
from pathlib import Path

proxy = sys.argv[1]
policies = json.loads(Path('/usr/local/share/app-isolation/firefox-policies.json').read_text())
if proxy:
    policies['policies']['Proxy'] = {
        'Mode': 'manual',
        'Locked': True,
        'SOCKSProxy': proxy,
        'SOCKSVersion': 5,
        'UseProxyForDNS': True,
    }
Path('/usr/lib/firefox-esr/distribution/policies.json').write_text(json.dumps(policies))
PY

exec xpra seamless :100 \
    --daemon=no \
    --bind-tcp="0.0.0.0:14500,auth=file(filename=$password_file),control=no" \
    --start-new-commands=no \
    --html=off \
    --mdns=no \
    --notifications=no \
    --exit-with-children=yes \
    --dpi=192 \
    --xvfb='Xvfb -screen 0 5120x5760x24 -dpi 192 -nolisten tcp +extension Composite +extension RANDR' \
    --start-child='env GDK_SCALE=2 XCURSOR_SIZE=48 firefox-esr' \
    --start-child="$code_command"
