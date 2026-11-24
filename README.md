<h1 align="center">
  <img src="assets/isolation-banner.jpg" width="100%" alt="Isolation">
</h1>

[![Platform][platform-badge]][docker-desktop]
[![Docker Compose][compose-badge]][docker-compose]
[![License][license-badge]][license]

**Isolation** runs Linux GUI apps in Docker on macOS. Each app opens in its own window and can access files in your Mac’s `Shared/` folder.

## How it works

The Xpra client on your Mac connects to the `applications` container through a password-protected port published on `127.0.0.1`.

The applications share a network namespace with the SSH gateway. The gateway routes outbound IPv4 TCP connections through the SSH tunnel, including connections from apps that ignore proxy settings. The local DNS resolver sends application queries over HTTPS through the same tunnel.

The gateway blocks external UDP and IPv6. If the tunnel goes down, the applications lose internet access until it is restored. Docker image builds and native macOS apps use the host’s network settings.

## Getting Started

### Requirements

- A Mac with Docker Desktop and Docker Compose. Isolation has been tested on Apple silicon. The installer can download Xpra for Apple silicon or Intel. [Install Docker Desktop for Mac][docker-desktop]
- A reachable SSH server, such as a VPS, with IPv4 connectivity, password authentication, and local TCP forwarding enabled for your SSH account. [OpenSSH forwarding options][ssh-forwarding]
- The SSH server's public host key, obtained through a trusted channel such as your VPS provider's console.

### Installation

From the project directory, copy the example and set the file permissions. The `-n` option creates `.env` only if it is missing.

```sh
cp -n .env_example .env
chmod 600 .env
```

From your VPS provider's console, print the type and key data of the server's public Ed25519 host key.

```sh
awk '{print $1, $2}' /etc/ssh/ssh_host_ed25519_key.pub
```

If the server is missing its host keys, run `sudo ssh-keygen -A` to generate them, then run the command above again. If the private host key already exists and you need its public part, run `sudo ssh-keygen -y -f /etc/ssh/ssh_host_ed25519_key`. [OpenSSH host key generation reference][ssh-host-keys]

Open `.env` and fill in your SSH settings. Keep the password in single quotes and paste the public host key into `DOCKER_GUI_SSH_HOST_KEY`.

```dotenv
DOCKER_GUI_SSH_HOST=ssh.example.com
DOCKER_GUI_SSH_PORT=22
DOCKER_GUI_SSH_USER=isolation
DOCKER_GUI_SSH_PASSWORD='replace-with-your-password'
DOCKER_GUI_SSH_HOST_KEY='ssh-ed25519 replace-with-the-server-public-key'
```

Run the installer to build both Docker images. It reuses an existing Xpra client or downloads and verifies the macOS application.

```sh
./scripts/manage.sh install
```

### Usage

#### Launch the apps

Double-click [`run.command`][launcher] in Finder or run `./run.command` from the project directory. Firefox ESR and VS Code open as separate Xpra windows with clipboard sharing enabled. Save your work before rerunning the launcher, which recreates the containers and starts a fresh session.

In Docker Desktop, look for the `app-isolation` project and its `applications` container.

#### Share files

Place files in `Shared/` on your Mac. The same directory is available at `/workspace` inside the container. VS Code opens it by default, and Firefox uses it for downloads.

#### Customize the installed apps

Add one APT package name per line to [`configs/apps.list`][app-list]. The default list installs `code` and `firefox-esr` for the launcher. For example, add `mousepad` to install the Mousepad editor. Run the installer again, launch a new session, and run `mousepad` from the VS Code terminal.

#### Set the time zone and locale

The defaults are `UTC` and `en_US.UTF-8`. Set `DOCKER_GUI_TZ` and `DOCKER_GUI_LANG` in `.env` before building, or pass both values to the installer.

```sh
./scripts/manage.sh install Europe/Berlin en_US.UTF-8
```

#### Verify the network route

Run both commands in the containerized VS Code terminal. Both should show your SSH server’s public exit IP. The second command ignores curl’s proxy settings and exercises the gateway’s transparent TCP forwarding.

```sh
curl https://api.ipify.org
curl --noproxy '*' https://api.ipify.org
```

### Uninstall

**Uninstall deletes `.env`, application profiles (including VS Code extensions and Firefox data), saved SSH host keys, and the Xpra password.** It also removes the project containers, volumes, images, and the project-managed Xpra app. Files in `Shared/` stay on your Mac.

```sh
./scripts/manage.sh uninstall
```

## License

Isolation is licensed under the [Apache License 2.0][license].

[platform-badge]: https://img.shields.io/badge/Platform-macOS-lightgrey
[compose-badge]: https://img.shields.io/badge/Runtime-Docker%20Compose-2496ED
[license-badge]: https://img.shields.io/badge/License-Apache%202.0-blue
[docker-desktop]: https://docs.docker.com/desktop/setup/install/mac-install/
[docker-compose]: https://docs.docker.com/compose/
[ssh-forwarding]: https://man.openbsd.org/sshd_config#AllowTcpForwarding
[ssh-host-keys]: https://man.openbsd.org/ssh-keygen#-A
[launcher]: run.command
[app-list]: configs/apps.list
[license]: LICENSE
