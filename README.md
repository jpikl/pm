# pm

Wrapper around various package managers with unified CLI.

- Supports: [pacman][pacman], [paru][paru], [yay][yay], [apt][apt], [dnf][dnf], [scoop][scoop].
- Interactive package selection using [fzf][fzf] with package info preview.
- A single self-contained script. Just copy it somewhere on the `$PATH` and you're good to go.
- POSIX compliant (will run literally everywhere).

![Demo usage](demo.gif)

## Usage

Run `pm help` for the usage:

```
Package manager wrapper (supports: paru yay pacman apt dnf)

Usage: pm <command>

Commands:
  i,  install          Interactively select packages to install.
  i,  install <pkg>... Install one or more packages.
  r,  remove           Interactively select packages to remove.
  r,  remove <pkg>...  Remove one or more packages.
  u,  upgrade          Upgrade all installed packages.
  f,  refresh          Refresh local package database.
  n,  info <pkg>       Print package information.
  la, list all         List all packages.
  li, list installed   List installed packages.
  sa  search all       Interactively search between all packages.
  si  search installed Interactively search between installed packages.
  w,  which            Print which package manager is being used.
  h,  help             Print this help.
```

## Features

### STDIN filter

Interactive commands can read additional filters from standard input.

- Each line is a regular expression (POSIX extended), matching whole package name.
- Hash sign `#` indicates the start of a comment (which is ignored).

```sh
echo "bat" >> favorite_pkgs.txt
echo "fzf" >> favorite_pkgs.txt
echo "ripgrep" >> favorite_pkgs.txt

# Interactively select favorite packages to install
pm install < favorite_pkgs.txt
```

### AUR helpers

On Arch Linux, `pm` allows easy installation of selected AUR helpers.

Just run `pm install <aur-helper>` where `<aur-helper>` is one of `paru`, `yay` or their binary variant (`paru-bin`, `yay-bin`).

These AUR helpers will be then used as the prefered package manager over `pacman`.

## Configuration

Configuration is done through the following environment variables

### PM

Enforces use of a specific package manager.

Options: `paru`, `yay`, `pacman`, `apt`, `dnf`.

The default package manager is auto detected by checking presence of the binaries listed above (in that particular order).

```shell
pacman pm install fzf    # Will auto detect package manager
PM=pacman pm install fzf # Will use pacman
PM=yay pm install fzf    # Will use yay
```

### PM_COLOR

Controls color output for non-interactive commands.

Options: `auto`, `always`, `never`.

The default is `auto` which outputs colors only when STDOUT is a TTY.

## FAQ

### How to select multiple packages in interactive mode?

Use the `TAB` key to (un)select multiple packages.

See [fzf docs](https://github.com/junegunn/fzf#using-the-finder) for more keyboard shortcuts.

### Is this better than my package manager?

Probably not, but it could be more convenient in some cases:

1. If you often switch between distros and you do not want to remember every package manager CLI.
2. Interactive package selection really helps when you are searching for a package to install and you do not know the exact name.

### Can you support package manager XYZ?

Just create [an issue](https://github.com/jpikl/pm/issues) for the support and I will look into that.

## License

`pm` is licensed under the [MIT license](LICENSE).

[apt]: https://salsa.debian.org/apt-team/apt
[dnf]: https://github.com/rpm-software-management/dnf
[fzf]: https://github.com/junegunn/fzf
[pacman]: https://wiki.archlinux.org/title/Pacman
[paru]: https://github.com/Morganamilo/paru
[scoop]: https://scoop.sh
[yay]: https://github.com/Jguer/yay
