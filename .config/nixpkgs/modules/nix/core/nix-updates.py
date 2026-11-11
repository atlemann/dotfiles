"""What an npins update changes on this machine.

Builds the system from the pins as they are now (without switching) and
compares it with the running one: the pins that moved, and the versions of
the packages installed through environment.systemPackages and home-manager,
of a few core packages, and of Emacs packages.  Only the summary is printed,
so it is cheap to read.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
import urllib.request
from pathlib import Path

DOTFILES = Path.home() / "src/dotfiles/.config/nixpkgs"
SOURCES = "npins/sources.json"
CORE = re.compile(r"^(linux|systemd|glibc|mesa|nvidia-x11|xorg-server|pipewire|nix|gcc)$")
OUTPUTS = re.compile(r"-(bin|lib|dev|man|doc|out|info|debug|data|unwrapped|wrapped)$")
# Sources and fixed-output helpers built alongside a package, named after it.
HELPERS = re.compile(r"(\.tar\.\w+|\.tgz|\.zip|-src|-source.*|-vendor.*|-go-modules|-deps|-binlore|-modules.*)$")
PATCHES = re.compile(r"\.(patch|diff)$")
DATE = re.compile(r"^\d{8}")
NOISE = re.compile(r"Merge |flake: (bump|update)|ci: ")

BOLD, DIM, RED, GREEN, YELLOW, CYAN = "1", "2", "31", "32", "33", "36"
COLOR = sys.stdout.isatty()


def paint(text, *codes):
    if not COLOR or not codes:
        return text
    return f"\033[{';'.join(codes)}m{text}\033[0m"


def run(*cmd, **kw):
    return subprocess.run(cmd, check=True, text=True, capture_output=True, **kw).stdout


# --- Pins ---

def pins_changed(old, new):
    """Yield (name, pin, old revision, new revision) for pins that moved."""
    for name, pin in new["pins"].items():
        before = old["pins"].get(name, {}).get("revision")
        if before != pin.get("revision"):
            yield name, pin, before, pin.get("revision")


def github_compare(owner, repo, old, new):
    url = f"https://api.github.com/repos/{owner}/{repo}/compare/{old}...{new}"
    request = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json"})
    if token := os.environ.get("GITHUB_TOKEN"):
        request.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return json.load(response)
    except Exception as error:  # rate limit, network: the URL is still printed
        return {"error": str(error)}


def show_pins(old, new, commits):
    changed = list(pins_changed(old, new))
    print(paint("Pins", BOLD))
    if not changed:
        print(paint("  none moved since the last commit", DIM))
    for name, pin, before, after in changed:
        repo = pin.get("repository", {})
        line = f"  {paint(name, BOLD, CYAN)} {paint(pin.get('branch') or pin.get('version') or '', DIM)}"
        if repo.get("type") != "GitHub" or not before:
            print(f"{line}  {(before or 'new')[:8]} → {after[:8]}")
            continue
        owner, name_ = repo["owner"], repo["repo"]
        data = github_compare(owner, name_, before, after)
        url = f"https://github.com/{owner}/{name_}/compare/{before[:12]}...{after[:12]}"
        if "error" in data:
            print(f"{line}  {paint(data['error'], RED)}")
        else:
            entries = data.get("commits", [])
            total = data.get("total_commits", 0)
            since = data["base_commit"]["commit"]["committer"]["date"][:10]
            print(f"{line}  {total} commits since {since}")
            # nixpkgs moves by thousands of commits; its titles say nothing.
            # The API lists at most 250 commits, oldest first.
            titles = [c["commit"]["message"].splitlines()[0] for c in entries
                      if not NOISE.match(c["commit"]["message"])]
            if total == len(entries) and len(titles) <= commits:
                for title in reversed(titles):
                    print(paint(f"    {title}", DIM))
        print(paint(f"    {url}", DIM))
    print()


# --- Closures ---

def parse_name(path):
    """Split a store path into (pname, version), as builtins.parseDrvName does."""
    name = Path(path).name[33:].removesuffix(".drv")
    if PATCHES.search(name):
        return name, ""
    match = re.search(r"-(?=[^a-zA-Z])", name)
    if not match:
        return name, ""
    return name[:match.start()], HELPERS.sub("", OUTPUTS.sub("", name[match.end():]))


def versions(paths):
    table = {}
    for path in paths:
        pname, version = parse_name(path)
        if version:
            table.setdefault(pname, set()).add(version)
    return table


def closure(drv):
    """The derivations a system is built from, build-time ones included."""
    return [p for p in run("nix-store", "--query", "--requisites", drv).split() if p.endswith(".drv")]


def direct(paths):
    """Packages installed on purpose: the inputs of system-path and home-manager-path."""
    found = set()
    for env in paths:
        if Path(env).name[33:] in ("system-path.drv", "home-manager-path.drv"):
            found.update(p for p in run("nix-store", "--query", "--references", env).split()
                         if p.endswith(".drv"))
    return found


def to_drv(path):
    if path.endswith(".drv"):
        return path
    drv = run("nix-store", "--query", "--deriver", os.path.realpath(path)).strip()
    if not Path(drv).exists():
        sys.exit(f"{path} has no derivation in the store to compare with")
    return drv


def bump(old, new):
    """Classify a version change as major, minor, patch or update."""
    a, b = (re.split(r"[.\-+_]", v) for v in (old, new))
    if DATE.match(old) and DATE.match(new):
        return "update"
    if a[0] != b[0]:
        return "major"
    if a[1:2] != b[1:2]:
        return "minor"
    return "patch"


def diff(old, new, names=None):
    rows = []
    for pname in sorted(set(old) | set(new)):
        if names is not None and pname not in names:
            continue
        before, after = old.get(pname, set()), new.get(pname, set())
        if before == after:
            continue
        if not before:
            rows.append(("added", pname, "", ", ".join(sorted(after))))
        elif not after:
            rows.append(("removed", pname, ", ".join(sorted(before)), ""))
        else:
            b, a = max(before), max(after)
            rows.append((bump(b, a), pname, ", ".join(sorted(before - after)), ", ".join(sorted(after - before))))
    return rows


KINDS = {"major": (RED, BOLD), "minor": (YELLOW,), "patch": (DIM,), "update": (DIM,),
         "added": (GREEN,), "removed": (RED,)}
ORDER = list(KINDS)


def show(title, rows, quiet=("patch", "update")):
    print(paint(f"{title} ({len(rows)})", BOLD))
    if not rows:
        print(paint("  no changes", DIM))
    rows.sort(key=lambda row: (ORDER.index(row[0]), row[1]))
    width = max((len(row[1]) for row in rows), default=0)
    folded = [row for row in rows if row[0] in quiet]
    for kind, pname, before, after in rows:
        if kind in quiet:
            continue
        change = after if not before else before if not after else f"{before} → {after}"
        print(f"  {paint(f'{kind:7}', *KINDS[kind])} {pname:{width}}  {change}")
    if folded:
        names = ", ".join(row[1] for row in folded)
        print(paint(f"  {len(folded)} smaller: {names}", DIM))
    print()


def nix_path(config):
    pin = run("nix", "eval", "--raw", "-f", str(DOTFILES / "npins/default.nix"), "nixpkgs")
    return dict(os.environ, NIX_PATH=f"nixpkgs={pin}:nixos-config={config}")


def evaluate(config):
    """Return the new system's derivation, reporting why it does not evaluate."""
    env = nix_path(config)
    for allow in ("", "1"):
        env["NIXPKGS_ALLOW_BROKEN"] = allow
        process = subprocess.run(["nix-instantiate", "<nixpkgs/nixos>", "-A", "config.system.build.toplevel",
                                  "--show-trace"], env=env, text=True, capture_output=True)
        if process.returncode == 0:
            return process.stdout.strip().splitlines()[-1]
        problem("Does not evaluate with the new pins:", process.stderr.splitlines())
        if allow or "broken" not in process.stderr:
            sys.exit(1)
        print(paint("  Comparing with NIXPKGS_ALLOW_BROKEN=1 instead.", DIM))
        print()


def build(config):
    """Build the new system, without switching; report why it fails to."""
    out = Path(tempfile.mkdtemp(prefix="nix-updates-"))
    print(paint(f"Building {config} ...", DIM), file=sys.stderr)
    process = subprocess.Popen(["nixos-rebuild", "build", "--no-reexec"], cwd=out, env=nix_path(config),
                               text=True, errors="replace", stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
    log = []
    for line in process.stderr:
        # nixos-rebuild's progress goes on to stderr, where it can be watched.
        sys.stderr.write(line)
        log.append(line.rstrip())
    if process.wait() == 0:
        print(paint(f"Builds: {(out / 'result').resolve()}", GREEN))
    else:
        problem("Does not build with the new pins:", log)
    print()


def problem(title, log):
    """Print the error of LOG, the problems listed under it, and what needs it."""
    errors = []
    for line in map(str.strip, log):
        # A trace opens with a bare "error:"; the message is the last one.
        if line.startswith("error:") and (line != "error:" or not errors):
            errors = [line]
        elif errors and errors[-1] and line.startswith(("- ", "Reason:")):
            errors.append(line)
        elif errors:
            errors.append("")
    errors = [line for line in errors if line] or log[-5:]
    # An evaluation trace runs from the outside in; failed builds are
    # listed from the inside out, the failing one first.
    chain = [m.group(1) for line in log if (m := re.search(r"while evaluating derivation '([^']+)'", line))][::-1]
    chain = chain or [parse_name(m.group(1))[0] for line in log
                      if (m := re.search(r"Cannot build '([^']+)'", line))][1:]
    print(paint(title, BOLD, RED))
    for line in errors:
        print(f"  {line}")
    if chain:
        print(f"  needed by: {' ← '.join(chain[:4])}")


def main():
    global COLOR
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--update", action="store_true", help="run `npins update` first")
    parser.add_argument("--build", action="store_true", help="also build the new system (without switching)")
    parser.add_argument("--system", help="compare with this system, or its .drv, instead of the pins")
    parser.add_argument("--config", default="/etc/nixos/configuration.nix")
    parser.add_argument("--against", default="/run/current-system")
    parser.add_argument("--all", action="store_true", help="also list every package in the closure that changed")
    parser.add_argument("--commits", type=int, default=30,
                        help="list a pin's commit titles when there are at most this many (default 30)")
    parser.add_argument("--color", action="store_true")
    args = parser.parse_args()
    COLOR = COLOR or args.color

    os.chdir(DOTFILES)
    old_sources = json.loads(run("git", "show", f"HEAD:./{SOURCES}"))
    if args.update:
        subprocess.run(["npins", "update"], check=True)
    new_sources = json.loads(Path(SOURCES).read_text())
    show_pins(old_sources, new_sources, args.commits)

    system = to_drv(args.system) if args.system else evaluate(args.config)
    if args.build:
        build(args.config)
    old_paths, new_paths = closure(to_drv(args.against)), closure(system)
    old_v, new_v = versions(old_paths), versions(new_paths)
    mine = {parse_name(p)[0] for p in direct(old_paths) | direct(new_paths)}

    show("Your packages", diff(old_v, new_v, mine))
    show("Core", diff(old_v, new_v, {n for n in set(old_v) | set(new_v) if CORE.match(n)}),
         quiet=())
    emacs = {n for n in set(old_v) | set(new_v) if n.startswith("emacs-")}
    show("Emacs packages", diff(old_v, new_v, emacs), quiet=("patch", "update"))
    if args.all:
        show("Everything else", diff(old_v, new_v, (set(old_v) | set(new_v)) - mine - emacs))
    print(paint(f"{args.against} → {system}", DIM))


if __name__ == "__main__":
    main()
