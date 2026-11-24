#!/bin/bash
set -eu

# Check sockets in LISTEN state without opening a redirection to redsocks itself.
awk '$4 == "0A" { listening[$2] = 1 }
    END { exit !(listening["0100007F:0438"] && listening["0100007F:3039"]) }' /proc/net/tcp
busybox nslookup example.org 127.0.0.1 >/dev/null
