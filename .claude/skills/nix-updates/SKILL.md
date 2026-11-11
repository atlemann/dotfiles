---
name: nix-updates
description: Check what an npins update (nixpkgs, home-manager, emacs-overlay, stylix) changes for this machine, by running the nix-updates script and summarising its output. Use when asked to check nixpkgs or the pins for updates, what changed in sources.json, or whether it is safe to switch.
---

# Checking pin updates

`nix-updates` (source: `.config/nixpkgs/modules/nix/core/nix-updates.py`)
does the expensive part and prints a short summary. Run it, don't
re-derive what it reports by diffing `sources.json` or querying the
store yourself.

## Run it

```sh
nix-updates            # compare the pins as they are now with the running system
nix-updates --update   # run `npins update` first, then compare
```

If `nix-updates` is not on PATH yet (no rebuild since it was added), run
`python3 ~/src/dotfiles/.config/nixpkgs/modules/nix/core/nix-updates.py`.

- It takes about two minutes, since it evaluates the whole system, so give
  the Bash call a 600000 ms timeout. Send stderr to a file
  (`2>/tmp/nix-updates.log`): that is evaluation noise, and stdout is the
  summary.
- Use `--update` only when the user asked to *update*. It rewrites
  `npins/sources.json`. When they ask to *check*, run without it: that
  compares whatever is pinned now, including uncommitted bumps.
- Pins are compared with the committed `sources.json`. Packages are
  compared with `/run/current-system`.
- Other flags:
  - `--build` also builds the new system, without switching. It catches
    build failures that evaluation can't, but downloads gigabytes, so run
    it only when the user wants to know whether a switch will work.
  - `--all` lists every changed dependency.
  - `--commits N` sets how many commit titles a pin may have before they
    are left out.

## Report

Lead with what blocks or risks a switch, then what the user would notice:

1. **"Does not evaluate/build with the new pins"**: the blocker. Name the
   package and the chain that pulls it in (the `needed by:` line), and
   check whether nixpkgs master has fixed it already:
   `curl -s "https://api.github.com/repos/NixOS/nixpkgs/commits?path=<dir of the package>&per_page=5"`.
   Then offer the options: keep the old pin, drop or override the
   package, or allow it in `nixpkgs.config` in `modules/nix/core`.
2. **Major bumps and downgrades** among *Your packages* and *Core*:
   - Major bumps: kernel, systemd, nvidia, mesa, desktop and terminal
     tools.
   - Downgrades show as "major" too (e.g. 79 → 78).
3. **Packages the user's own config depends on**. Point these out when
   they move:
   - glab (mr-dash, magit-glab), git, tmux, direnv, Emacs and its
     packages (eglot, magit, transient, corfu), herdr and claude-code.
   - Name them; don't list every minor bump.
4. Pins that moved only by flake/CI bumps get one line.

Keep it to a short table or list. Version numbers are compared as text,
so a `p15 → p20` patch can show up as "minor": use judgement. Don't open
upstream changelogs unless asked, or a major bump of something central
(systemd, kernel, Emacs) warrants a look.

Never switch (`nixos-switch`) or commit the pins without being asked.
