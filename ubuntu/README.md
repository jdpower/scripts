# initial-setup.sh

Bootstraps a Zsh + Oh My Zsh + Powerlevel10k terminal setup on a fresh
Ubuntu/Debian machine. Companion reference: [initial-setup.md](initial-setup.md).

## Usage

```bash
bash initial-setup.sh              # apply all changes
bash initial-setup.sh --dry-run    # preview every action without changing anything
bash initial-setup.sh --help       # show usage
```

Run as a normal user, **not** root/`sudo` — the script calls `sudo` itself
wherever it's needed and refuses to run if invoked as root (`EUID == 0`).

## What it does

Runs through 7 steps in order, each idempotent (safe to re-run — every step
checks whether its work is already done before doing it):

1. **Install APT packages** — `zsh`, `net-tools`, `fonts-font-awesome`,
   `lm-sensors`, `hardinfo`, `glances`, `apt-transport-https`, `curl`, `git`
2. **Set Zsh as the default shell** via `chsh` (skipped if already set)
3. **Install Oh My Zsh** (skipped if `~/.oh-my-zsh` already exists)
4. **Install MesloLGS Nerd Fonts** (Regular/Bold/Italic/Bold Italic) to
   `~/.local/share/fonts`, then refreshes the font cache — required for
   Powerlevel10k's icons to render correctly. **Skipped on a headless/server
   install** (detected via `is_desktop()` — checks for an installed desktop
   metapackage/display server package, or `$DISPLAY`/`$WAYLAND_DISPLAY`):
   the font only matters for a local GUI terminal emulator running on the
   same machine, which a server doesn't have. If you SSH into a server from
   a client with its own GUI terminal, install the font on that client
   instead.
5. **Install Powerlevel10k** — clones the theme and sets `ZSH_THEME` in
   `~/.zshrc`
6. **Install Zsh plugins** — clones `zsh-autosuggestions` and
   `zsh-syntax-highlighting`
7. **Configure `~/.zshrc`** — updates the `plugins=(...)` line to include
   `git`, `zsh-autosuggestions`, `zsh-syntax-highlighting`; prepends the
   Powerlevel10k instant-prompt block; appends the line to source
   `~/.p10k.zsh` if present

Before any of that, it also checks: not running as root, running on a
Debian/Ubuntu system (`/etc/debian_version` exists), and that it has
internet connectivity (`curl` to github.com).

## `--dry-run`

Every step supports `--dry-run`: it prints exactly what command would run
or what would be written to a file (prefixed `[DRY-RUN]`), without actually
installing packages, cloning repos, downloading fonts, or touching
`~/.zshrc`. Useful for reviewing the full plan before committing to it,
especially over SSH on a machine you don't want to accidentally lock out of
its shell.

## After it finishes

- **Desktop installs**: set your terminal emulator's font to **MesloLGS NF**
  (required for Powerlevel10k's icons — instructions are printed in the
  summary for GNOME Terminal, Konsole, and VS Code)
- **Headless/server installs**: the summary skips the font step and instead
  reminds you to set the font on whatever client you SSH in from
- Log out and back in (or open a new terminal) for the shell change to
  take effect
- The Powerlevel10k configuration wizard launches automatically on first
  Zsh login; re-run it any time with `p10k configure`
