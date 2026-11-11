# Emacs IDE cheat sheet

What `configuration.org` sets up, and how to reach it. `C-` = Ctrl, `M-` = Alt,
`S-` = Shift. Lost? Press `C-h` in the middle of any prefix (which-key / embark
shows what follows), or `C-h B` to search every binding.

## Language server status

The mode line (left of the encoding) shows what the language server is doing,
so you know when IDE features are ready:

- `LSP starting…` — server process launched, handshake not done yet.
- `Loading 12 Projects`, `Typechecking Foo.fs`, … — the server's own progress
  reports. When it clears, everything is live.
- `Foo.fsproj failed to load` (red) — fsautocomplete gave up on a project;
  a message says why (usually missing packages). Run `dotnet restore`, then
  `M-x eglot-reconnect`. Details: `M-x eglot-events-buffer`.

## Navigating code (eglot + xref)

| Key | What |
|---|---|
| `M-.` | Go to definition |
| `M-,` | Jump back |
| `M-?` | Find references |
| `C-c s` | Go to workspace symbol (consult-eglot, Rider-ish "Go to Symbol") |
| `M-n` / `M-p` | Next / previous occurrence of the symbol at point |
| `C-h .` | Docs box right at point (`C-g` closes it); `M-x eldoc-doc-buffer` for a full window |

Docs for the symbol at point pop up in a box in the top-right corner (and a
short signature in the echo area). Breadcrumb in the header line shows namespace → class → method. Eglot
highlights the symbol at point automatically.

## Refactoring and editing

| Key | What |
|---|---|
| `M-RET` | Code actions (quick fixes, add open, …) |
| `<f2>` | Rename symbol across the project |
| `C-c m n` / `C-c m p` | Multiple cursors: mark next / previous like this (GUI also `C->` / `C-<`) |
| `C-c m a` | Multiple cursors: mark all like this |
| `C-c m l` | Multiple cursors on each line of the region |
| `C-g` | Leave multiple-cursors mode |
| `M-i` | Pin a coloured highlight on the symbol at point (stackable) |
| `C-c i` | Remove all pinned highlights |

**Format on save** is automatic (apheleia): fantomas for F#, plus apheleia's
built-in formatters for other languages when the tool is on PATH. Rust uses
rustic's own format-on-save. If an F# save doesn't format, check the
`*apheleia-fantomas-log*` buffer.

## Completion

- Completion pops up as you type (corfu). `TAB`/`RET` accepts, `C-n`/`C-p` or
  arrows move, `C-g` closes.
- LSP snippet completions (function arguments etc.) expand via yasnippet;
  `TAB` jumps to the next field.
- Completion sources also include words from open buffers and file paths (cape).

## Diagnostics (flycheck)

Errors and warnings are drawn inline on a virtual line under the code
(`╰┈┈► message`, flyover), Neovim-style. With the cursor on one, the eldoc box
also shows it, plus any quick fix (`M-RET`). Info-level hints are only counted
in the mode line.

| Key | What |
|---|---|
| `M-g f` | Jump to an error/warning from a filterable list |
| `C-c ! l` | List all errors in a buffer |
| `C-c ! n` / `C-c ! p` | Next / previous error |

## Search and project

| Key | What |
|---|---|
| `C-s` | Search in buffer (consult-line) |
| `C-M-j` | Switch buffer (consult-buffer, with recent files) |
| `C-c p` | Projectile prefix |
| `C-c p SPC` | Find file in project |
| `C-c p r` | Ripgrep the project (consult-ripgrep) |
| `M-0` | Treemacs file tree |
| `C-x C-j` | Dired at the current file |

**Project-wide search and replace:** `C-c p r` → type the search → `M-o E`
(embark export to a grep buffer) → `C-c C-p` (make it editable) → edit, e.g.
with `M-%` → `C-c C-c` writes every file.

## Embark (act on anything)

| Key | What |
|---|---|
| `M-o` (or `C-.` in GUI) | Action menu for thing at point or minibuffer candidate |
| `C-;` | Do the default action for thing at point |
| `M-o E` (in minibuffer) | Export the candidate list to a buffer |
| `C-h B` | Search all key bindings |

## Debugging (dape + netcoredbg)

| Key | What |
|---|---|
| `<f5>` | Start a debug session (F# and C# use netcoredbg) |
| `C-c b` | Toggle breakpoint |
| `<f10>` | Step over |
| `<f11>` / `S-<f11>` | Step in / step out |
| `C-x C-a c` | Continue |
| `C-x C-a r` | Restart |
| `C-x C-a x` | Evaluate an expression |
| `C-x C-a w` | Watch the expression at point |
| `C-x C-a R` | Debugger REPL |
| `C-x C-a i` | Info panes (locals, stack, breakpoints) |
| `C-x C-a D` | Stop and quit |

`C-x C-a` is dape's prefix; after one command you can keep pressing just the
final key (`n`, `s`, `c`, …).

## .NET (dotnet-mode in F#/C# buffers)

| Key | What |
|---|---|
| `C-c t t` | Run tests |
| `C-c t b` | Build |
| `C-c t r` | Run |

## Git

| Key | What |
|---|---|
| `C-x g` | Magit status |
| `C-x v [` / `C-x v ]` | Previous / next changed hunk (diff-hl) |
| `C-x v *` | Show the hunk diff inline |
| `C-x v n` | Revert hunk |
| `C-x v S` | Stage hunk |

The margin shows added/changed/deleted lines, updated live before you save.
Magit diffs are syntax-highlighted per language (`M-x my/magit-syntax-mode`
toggles). In magit's push menu, `R` pushes to Gerrit.

### Review comments to a herdr agent

| Key | What |
|---|---|
| `C-c r c` | Comment on the marked lines (magit diff or any file) |
| `C-c r d` | Delete the comment on this line |
| `C-c r s` | Send all comments to the workspace's agent pane |
| `C-c r k` | Discard all comments |

## Folding (treesit-fold)

| Key | What |
|---|---|
| `C-c f` | Fold / unfold the node at point |
| `C-c F` | Unfold everything |

Works in C#, Nix, Python, Rust, …; not F# (there's no F# grammar for it yet).

## Rust (rustic buffers)

| Key | What |
|---|---|
| `C-c C-c r` / `t` / `f` | Cargo run / test / fmt |
| `C-c C-c l` | List errors |
| `C-c C-c a` | Cargo apropos |

## Other bits

- `M-x eat` / `M-x eat-project`: terminal inside Emacs (at the project root).
- TODO / FIXME / HACK keywords are highlighted (hl-todo).
- envrc picks up each project's direnv / Nix dev shell, so language servers
  and formatters come from the project's own toolchain.
- LSP traffic goes through emacs-lsp-booster (eglot-booster) to keep things
  snappy.
- F# buffers show indent guides; all code buffers get rainbow delimiters and
  smartparens.
- Buffers over 1 MB switch off the expensive modes automatically.
- `C-h f` / `C-h v` / `C-h k`: helpful's richer help pages.
