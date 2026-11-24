#!/bin/bash
set -euo pipefail

if [[ -z ${SSH_PROXY_HOST:-} || -z ${SSH_PROXY_USER:-} || ! -s /run/secrets/ssh_password ]]; then
    printf '%s\n' 'Set DOCKER_GUI_SSH_HOST, DOCKER_GUI_SSH_USER, and DOCKER_GUI_SSH_PASSWORD in .env.' >&2
    exit 1
fi

ssh_port=${SSH_PROXY_PORT:-22}
if [[ ! $SSH_PROXY_HOST =~ ^[[:alnum:]][[:alnum:].-]*$ || ! $ssh_port =~ ^[1-9][0-9]{0,4}$ ]] || (( ssh_port > 65535 )); then
    printf '%s\n' 'Set an IPv4 address or hostname for the SSH server and a valid port in .env.' >&2
    exit 1
fi

# Resolve only the transport endpoint using Docker DNS. The desktop uses the local DoH stub.
ssh_ip=$(getent ahostsv4 "$SSH_PROXY_HOST" | awk 'NR == 1 { print $1 }') || {
    printf '%s\n' 'Could not resolve the IPv4 address of the SSH server.' >&2
    exit 1
}
[[ -n $ssh_ip ]]
host_key_alias=$SSH_PROXY_HOST
if [[ $ssh_port != 22 ]]; then
    host_key_alias="[$SSH_PROXY_HOST]:$ssh_port"
fi

known_hosts_file=/var/lib/ssh-proxy/known_hosts
if [[ -n ${SSH_PROXY_HOST_KEY:-} ]]; then
    if [[ $SSH_PROXY_HOST_KEY == *$'\n'* || $SSH_PROXY_HOST_KEY == *$'\r'* ]]; then
        printf '%s\n' 'Set DOCKER_GUI_SSH_HOST_KEY to a single SSH public host key.' >&2
        exit 1
    fi
    known_hosts_file=/run/app-isolation-known-hosts
    printf '%s %s\n' "$host_key_alias" "$SSH_PROXY_HOST_KEY" > "$known_hosts_file"
    if ! ssh-keygen -l -f "$known_hosts_file" >/dev/null 2>&1; then
        printf '%s\n' 'DOCKER_GUI_SSH_HOST_KEY must contain a valid SSH public host key.' >&2
        exit 1
    fi
    chmod 644 "$known_hosts_file"
else
    # Keep the pinned key when upgrading an existing installation.
    if ! ssh-keygen -F "$host_key_alias" -f "$known_hosts_file" >/dev/null 2>&1; then
        printf '%s\n' 'Set DOCKER_GUI_SSH_HOST_KEY to the public host key obtained from a trusted VPS console.' >&2
        exit 1
    fi
    chown ssh-proxy:ssh-proxy /var/lib/ssh-proxy "$known_hosts_file"
fi
{
    printf 'define ssh_ip = %s\ndefine ssh_port = %s\n' "$ssh_ip" "$ssh_port"
    cat /etc/app-isolation/firewall.nft
} | nft -f -

pids=()
trap 'if (( ${#pids[@]} )); then kill "${pids[@]}" 2>/dev/null || true; fi' EXIT
trap 'exit 143' TERM
trap 'exit 130' INT

setpriv --reuid=1001 --regid=1001 --clear-groups \
    sshpass -f /run/secrets/ssh_password ssh -4 -N -T \
    -D 127.0.0.1:1080 \
    -o ConnectTimeout=10 \
    -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=15 \
    -o ServerAliveCountMax=3 \
    -o NumberOfPasswordPrompts=1 \
    -o PreferredAuthentications=password,keyboard-interactive \
    -o StrictHostKeyChecking=yes \
    -o GlobalKnownHostsFile=/dev/null \
    -o UserKnownHostsFile="$known_hosts_file" \
    -o UpdateHostKeys=no \
    -o Hostname="$ssh_ip" -o HostKeyAlias="$host_key_alias" \
    -p "$ssh_port" -l "$SSH_PROXY_USER" -- "$SSH_PROXY_HOST" &
pids+=("$!")

setpriv --reuid=65534 --regid=65534 --clear-groups redsocks -c /etc/app-isolation/redsocks.conf &
pids+=("$!")
setpriv --reuid=65534 --regid=65534 --clear-groups dnscrypt-proxy -config /etc/app-isolation/dnscrypt-proxy.toml &
pids+=("$!")

wait -n || exit $?
exit 1
