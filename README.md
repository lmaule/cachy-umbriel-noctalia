# cachy-umbriel-noctalia

[![ShellCheck](https://github.com/lmaule/cachy-umbriel-noctalia/actions/workflows/shellcheck.yml/badge.svg)](https://github.com/lmaule/cachy-umbriel-noctalia/actions/workflows/shellcheck.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)

One script that turns a fresh **CachyOS "No Desktop"** install into a working
desktop built entirely from the [Noctalia](https://github.com/noctalia-dev) stack:

| Component | What it is | Source |
|---|---|---|
| [Umbriel](https://github.com/noctalia-dev/umbriel) | Wayland compositor (scrolling, dwindle, master layouts) | AUR `umbriel-git` |
| [Noctalia](https://github.com/noctalia-dev/noctalia) | Desktop shell – bar, launcher, control centre, notifications | `extra/noctalia` |
| [Luciole](https://github.com/noctalia-dev/luciole) | File manager | AUR `luciole-git` |
| [Noctalia Greeter](https://github.com/noctalia-dev/noctalia-greeter) | Login screen for greetd | `extra/noctalia-greeter` |

## Requirements

- A fresh CachyOS install with the **No Desktop** option selected
- A normal user account with `sudo` rights
- An internet connection (on Wi-Fi, connect first with `nmtui`)

## Usage

Log in at the TTY as your normal user (not root) and run:

```sh
curl -LO https://raw.githubusercontent.com/lmaule/cachy-umbriel-noctalia/main/install.sh
bash install.sh
```

Download the script first rather than piping it into `bash`, because it asks
yes/no questions. The whole run is logged to `~/noctalia-install-<date>.log`.

Or clone the whole repo (git is preinstalled on CachyOS):

```sh
git clone https://github.com/lmaule/cachy-umbriel-noctalia.git
cd cachy-umbriel-noctalia
./install.sh
```

## What the script does

0. **Pre-flight**: refuses to run as root, checks for CachyOS/Arch and internet, caches your sudo password
1. **Updates** the system (`pacman -Syu`)
2. **Installs** `base-devel`, XDG portals and Xwayland (everything else already ships with CachyOS)
3. **Sets up an AUR helper**: uses paru or yay if one is installed, otherwise installs paru
4. **Installs Noctalia** from the official repos
5. **Builds Umbriel and Luciole** from the AUR
6. **Configures Umbriel** in `~/.config/umbriel/`:
   - `base.toml` is a copy of Umbriel's example config
   - `noctalia.toml` autostarts Noctalia and adds its keybinds, window rules and blur
   - `config.toml` loads both. Put your own changes at the bottom, where they override everything else
7. **Installs greetd and Noctalia Greeter**, pre-selects your user and the Umbriel session, and enables greetd
8. **Offers to reboot**

The script is safe to re-run: packages use `--needed` and existing configs are
backed up (`*.bak.<timestamp>`) instead of being overwritten.

## Default keybinds

| Keys | Action |
|---|---|
| `Super` + `Return` | Terminal (alacritty) |
| `Super` + `Space` | Launcher |
| `Super` + `S` | Control centre |
| `Super` + `E` | Luciole |
| `Super` + `,` | Noctalia settings |
| `Alt` + `Tab` | Window switcher |
| `Super` + `Shift` + `A` | Screenshot + annotate |

## Customising

Edit the settings block at the top of `install.sh`:

- `TERMINAL_PKG`: the terminal bound to `Super` + `Return`
- `EXTRA_PKGS`: extra packages installed in step 2
- `ENABLE_GREETER`: set to `false` to keep booting into the TTY (then start the desktop with `start-umbriel`)

## Updating

Umbriel and Luciole are `-git` packages, so update them along with the rest of the system using your AUR helper:

```sh
paru -Syu
```

Re-running `install.sh` is also safe. It refreshes `~/.config/umbriel/noctalia.toml` but leaves `base.toml`
and your own `config.toml` untouched.

## After installing

To make the login screen match your desktop theme, open Noctalia → Settings → Security → Noctalia Greeter and choose
**Sync Now**.

## Troubleshooting

- **The login screen doesn't appear or crashes:** press `Ctrl` + `Alt` + `F2`, log in, and run
  `sudo systemctl disable greetd` to go back to TTY login. Logs are in
  `/var/log/noctalia-greeter.log` and `/var/lib/noctalia-greeter/greeter.log`.
- **Umbriel config errors:** run `umbriel config validate`.
- **The install failed partway:** check the log file in your home folder, fix the problem, and re-run the script.

## License

[MIT](LICENSE)
