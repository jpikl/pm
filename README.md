# pm

Wrapper around various package managers with unified CLI.

- Supports: `pacman`, `yay`, `apt`, `dnf`.
- Interactive package selection using [fzf](https://github.com/junegunn/fzf) with package info preview.
- A single self-contained script. Just copy it somewhere on the `$PATH` and you're good to go.
- POSIX compliant (will run literally everywhere). 

![Demo usage](demo.gif)

## Usage

Run `pm help` to get the usage.

```
Package manager wrapper (supports: yay pacman apt dnf)

Usage: pm <command>

Commands:
  i, install          Interactively select packages to install
  i, install <pkg>... Install one or more packages
  u, upgrade          Upgrade all installed packages
  r, remove           Interactively select packages to remove
  r, remove <pkg>...  Remove one or more packages
  n, info <pkg>       Print package information
  l, list <source>    List packages (source: installed, available)
  li                  Alias for 'list installed'
  la                  Alias for 'list available'
  s, search <source>  Interactively search packages (source: installed, available)
  si                  Alias for 'search installed'
  sa                  Alias for 'search available'
  f, refresh          Refresh local package database
  h, help             Print this help
```

## FAQ

### How to enforce a specific packager manager?

Use the `PM` environment variable

```shell
PM=pacman pm install fzf # Will use pacman
PM=yay pm install fzf    # Will use yay
```

### How to select multiple packages in interactive mode?

Use the `TAB` key to (un)select multiple packages.

### Is this better than my package manager?

Probably not, but it could be more convenient in some cases:

1. If you often switch between distros and you do not want to remember every package manager CLI.
2. Interactive package selection really helps when you are searching for a package to install and you do not know the exact name.

### Can you support package manager XYZ?

Just create [an issue](https://github.com/jpikl/pm/issues) for the support and I will look into that.

## License

`pm` is licensed under the [MIT license](LICENSE).
