"""mr-dash: a Gerrit-like dashboard of GitLab merge request stacks.

Lists the stacks you have pushed (outgoing) and the stacks you are asked to
review (incoming). In a stack each merge request targets the source branch of
the one below it. Every merge request shows its CI status, its unresolved
threads, the state of each reviewer, and whose turn it is.

Whose turn it is works like Gerrit's attention set:
  - a reviewer is up while their review is pending, or when the author has
    changed the code or replied since the reviewer last acted (a push that only
    rebases, compared by patch-id, doesn't count);
  - the author is up when CI failed, the branch conflicts, someone else wrote
    the last note in an unresolved thread, a reviewer is waiting for changes,
    there are no reviewers, or the merge request is ready to merge.

Usage:
  mr-dash             print the dashboard
  mr-dash -i          browse it in fzf (enter: open in browser, alt-d: diff since
                      you acted, alt-w: review in a herdr worktree, alt-n: push
                      its versions to nit, ctrl-r: reload, ?: toggle preview)
  mr-dash --nit <project> <iid>
                      push every version of the merge request, and of the ones
                      below it, to nit from its worktree, oldest first
  mr-dash --interdiff <project> <iid>
                      diff the version you last acted on with the latest, rebased
                      so changes in the stack below don't show up
  mr-dash --worktree <project> <iid>
                      open a herdr workspace on a worktree of the merge request,
                      under its repo; a worktree already there moves to the latest
                      version, unless that would lose work
"""

import argparse
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
import textwrap
from concurrent.futures import ThreadPoolExecutor
from datetime import datetime, timezone

DETAIL_BATCH = 4  # small queries in parallel beat big ones

DETAIL_FIELDS = """
  iid title webUrl draft sourceBranch targetBranch updatedAt conflicts
  approvalsLeft
  author { username }
  headPipeline { status }
  reviewers { nodes { username bot mergeRequestInteraction { reviewState } } }
  discussions(first: 100) {
    nodes {
      resolvable resolved
      notes(first: 100) { nodes { system author { username } createdAt } }
    }
  }
"""


def graphql(query):
    out = subprocess.run(
        ["glab", "api", "graphql", "-f", f"query={query}"],
        check=True, capture_output=True, text=True,
    ).stdout
    data = json.loads(out)
    if data.get("errors"):
        sys.exit(f"mr-dash: GraphQL error: {data['errors']}")
    return data["data"]


def fetch_me():
    data = graphql("""
      query {
        currentUser {
          username
          authoredMergeRequests(state: opened, first: 100) { nodes { project { fullPath } } }
          reviewRequestedMergeRequests(state: opened, first: 100) { nodes { project { fullPath } } }
        }
      }""")
    user = data["currentUser"]
    mrs = (user["authoredMergeRequests"]["nodes"]
           + user["reviewRequestedMergeRequests"]["nodes"])
    return user["username"], sorted({mr["project"]["fullPath"] for mr in mrs})


def fetch_open(project):
    """All open merge requests of the project, with just enough to find stacks."""
    mrs, after = [], None
    while True:
        cursor = f", after: {json.dumps(after)}" if after else ""
        data = graphql(f"""
          query {{
            project(fullPath: {json.dumps(project)}) {{
              mergeRequests(state: opened, first: 100{cursor}) {{
                pageInfo {{ hasNextPage endCursor }}
                nodes {{
                  iid sourceBranch targetBranch
                  author {{ username }}
                  reviewers {{ nodes {{ username }} }}
                }}
              }}
            }}
          }}""")
        page = data["project"]["mergeRequests"]
        mrs += page["nodes"]
        if not page["pageInfo"]["hasNextPage"]:
            return mrs
        after = page["pageInfo"]["endCursor"]


def fetch_details(project, iids):
    def batch(chunk):
        data = graphql(f"""
          query {{
            project(fullPath: {json.dumps(project)}) {{
              mergeRequests(iids: {json.dumps(chunk)}, first: {len(chunk)}) {{
                nodes {{ {DETAIL_FIELDS} }}
              }}
            }}
          }}""")
        return data["project"]["mergeRequests"]["nodes"]

    chunks = [iids[i:i + DETAIL_BATCH] for i in range(0, len(iids), DETAIL_BATCH)]
    with ThreadPoolExecutor(max_workers=16) as pool:
        versions = {iid: pool.submit(fetch_versions, project, iid) for iid in iids}
        mrs = {mr["iid"]: mr for nodes in pool.map(batch, chunks) for mr in nodes}
    for iid, mr in mrs.items():
        mr["versions"] = versions[iid].result()
    return mrs


def fetch_versions(project, iid):
    """The pushed versions of the merge request, oldest first, like Gerrit's patchsets."""
    out = subprocess.run(
        ["glab", "api", f"projects/{project.replace('/', '%2F')}/merge_requests/{iid}/versions?per_page=100"],
        capture_output=True, text=True,
    )
    if out.returncode != 0:
        return []
    return [{"created": parse_time(v["created_at"]), "head": v["head_commit_sha"],
             "base": v["base_commit_sha"], "patch": v.get("patch_id_sha") or v["head_commit_sha"]}
            for v in reversed(json.loads(out.stdout))]


class Stack:
    def __init__(self, project, root, children):
        self.project = project
        self.root = root
        self.children = children
        self.mrs = {}

    def walk(self, iid=None, depth=0):
        """(iid, depth) pairs, lowest first; a fork indents the branches above it."""
        iid = iid or self.root
        yield iid, depth
        kids = self.children.get(iid, [])
        for kid in kids:
            yield from self.walk(kid, depth + (len(kids) > 1))


def find_stacks(project, open_mrs, me):
    by_source = {mr["sourceBranch"]: mr for mr in open_mrs}
    parent, children = {}, {}
    for mr in open_mrs:
        below = by_source.get(mr["targetBranch"])
        if below and below["iid"] != mr["iid"]:
            parent[mr["iid"]] = below["iid"]
            children.setdefault(below["iid"], []).append(mr["iid"])
    for kids in children.values():
        kids.sort(key=int)

    def root_of(iid):
        seen = set()
        while iid in parent and iid not in seen:
            seen.add(iid)
            iid = parent[iid]
        return iid

    roots = {}
    for mr in open_mrs:
        mine = mr["author"]["username"] == me
        asked = any(r["username"] == me for r in mr["reviewers"]["nodes"])
        if mine or asked:
            roots.setdefault(root_of(mr["iid"]), Stack(project, root_of(mr["iid"]), children))
    return list(roots.values())


def parse_time(stamp):
    return datetime.fromisoformat(stamp.replace("Z", "+00:00"))


def last_activity(mr, spoken=False):
    """Map of username -> when they last left a note (just comments with <spoken>)."""
    last = {}
    for disc in mr["discussions"]["nodes"]:
        for note in disc["notes"]["nodes"]:
            if note["author"] and not (spoken and note["system"]):
                user, when = note["author"]["username"], parse_time(note["createdAt"])
                last[user] = max(last.get(user, when), when)
    return last


def patchsets(mr, since):
    """(seen, latest, changed): the version numbers seen at time <since> and now, and
    whether the code changed in between, ignoring rebases. None without versions."""
    versions = mr.get("versions")
    if not versions:
        return None
    seen = sum(v["created"] <= since for v in versions) if since else 0
    latest = len(versions)
    changed = seen < latest and (seen == 0 or versions[seen - 1]["patch"] != versions[-1]["patch"])
    return seen, latest, changed


def attention(mr, at_bottom):
    """Map of username -> reasons it is their turn on the merge request."""
    author = mr["author"]["username"]
    turn = {}

    def add(user, reason):
        turn.setdefault(user, []).append(reason)

    last, spoken = last_activity(mr), last_activity(mr, spoken=True)

    if mr["draft"]:
        add(author, "draft")
    if (mr["headPipeline"] or {}).get("status") == "FAILED":
        add(author, "CI failed")
    if mr["conflicts"]:
        add(author, "conflicts")

    unresolved = [d for d in mr["discussions"]["nodes"] if d["resolvable"] and not d["resolved"]]
    for disc in unresolved:
        notes = [n for n in disc["notes"]["nodes"] if not n["system"] and n["author"]]
        if not notes:
            continue
        starter, writer = notes[0]["author"]["username"], notes[-1]["author"]["username"]
        if writer != author:
            add(author, "reply to threads")
        elif starter != author and not starter_is_bot(mr, starter):
            add(starter, "author replied")
        else:
            add(author, "resolve threads")

    humans = [r for r in mr["reviewers"]["nodes"] if not r["bot"] and r["username"] != author]
    if not humans:
        add(author, "add reviewers")
    for rev in humans:
        user = rev["username"]
        state = (rev["mergeRequestInteraction"] or {}).get("reviewState")
        if state == "APPROVED":
            continue
        sets = patchsets(mr, last.get(user))
        if state == "REVIEW_STARTED" or user not in last:
            add(user, "review")
        elif sets and sets[2]:
            add(user, "re-review")
        elif sets and spoken.get(author, last[user]) > last[user]:
            add(user, "author replied")
        elif not sets and last.get(author, last[user]) > last[user]:
            add(user, "re-review")
        elif state == "REQUESTED_CHANGES":
            add(author, "changes requested")
        elif state == "REVIEWED":
            add(author, "reviewed")
        else:
            add(user, "review")

    status = (mr["headPipeline"] or {}).get("status")
    if turn or status in ("RUNNING", "PENDING", "CREATED", "PREPARING", "WAITING_FOR_RESOURCE"):
        pass
    elif status != "SUCCESS":
        add(author, f"CI {status.lower()}" if status else "no CI")
    elif mr["approvalsLeft"]:
        add(author, "needs more approvals")
    elif not unresolved:
        add(author, "merge" if at_bottom else "merge after the MR below")

    # Reasons in the order they were found, without repeats.
    return {user: list(dict.fromkeys(reasons)) for user, reasons in turn.items()}


def starter_is_bot(mr, user):
    return any(r["username"] == user and r["bot"] for r in mr["reviewers"]["nodes"])


# --- Rendering ---------------------------------------------------------------

COLOR = sys.stdout.isatty() and "NO_COLOR" not in os.environ


def paint(text, *codes):
    if not COLOR or not codes:
        return text
    return f"\033[{';'.join(codes)}m{text}\033[0m"


BOLD, DIM, RED, GREEN, YELLOW, BLUE, MAGENTA, CYAN = "1", "2", "31", "32", "33", "34", "35", "36"

CI = {
    "SUCCESS": ("✔", GREEN), "FAILED": ("✘", RED), "RUNNING": ("●", YELLOW),
    "PENDING": ("○", YELLOW), "CREATED": ("○", YELLOW), "WAITING_FOR_RESOURCE": ("○", YELLOW),
    "PREPARING": ("○", YELLOW), "SCHEDULED": ("○", YELLOW), "MANUAL": ("▶", BLUE),
    "CANCELED": ("⊘", DIM), "SKIPPED": ("»", DIM),
}

REVIEW = {
    "APPROVED": ("✔", GREEN), "REQUESTED_CHANGES": ("✘", RED), "REVIEWED": ("✎", YELLOW),
    "REVIEW_STARTED": ("…", YELLOW), "UNREVIEWED": ("◌", DIM), "UNAPPROVED": ("◌", DIM),
}


def visible_len(text):
    out, skip = 0, False
    for ch in text:
        if ch == "\033":
            skip = True
        elif skip and ch == "m":
            skip = False
        elif not skip:
            out += 1
    return out


def pad(text, width):
    return text + " " * max(0, width - visible_len(text))


def age(stamp):
    secs = (datetime.now(timezone.utc) - parse_time(stamp)).total_seconds()
    for unit, size in (("d", 86400), ("h", 3600), ("m", 60)):
        if secs >= size:
            return f"{int(secs // size)}{unit}"
    return "now"


def short(user, me):
    return "you" if user == me else user.split(".")[0]


def row(mr, depth, turn, me, show_author):
    author = mr["author"]["username"]
    involved = author == me or any(r["username"] == me for r in mr["reviewers"]["nodes"])
    mine = me in turn
    marker = paint("▶", BOLD, YELLOW) if mine else " "

    status = (mr["headPipeline"] or {}).get("status")
    glyph, color = CI.get(status, ("–", DIM))
    ci = paint(glyph, color)

    threads = [d for d in mr["discussions"]["nodes"] if d["resolvable"]]
    open_ = sum(not d["resolved"] for d in threads)
    talk = paint(f"{open_}/{len(threads)}", RED if open_ else DIM) if threads else paint("–", DIM)

    # As a reviewer: what was pushed since you last acted.
    sets = patchsets(mr, last_activity(mr).get(me)) if author != me and involved else None
    if sets and 0 < sets[0] < sets[1]:
        seen, latest, changed = sets
        version = (paint(f"v{seen}→{latest}", BOLD, YELLOW) if changed
                   else paint(f"v{seen}≈{latest}", DIM))
    else:
        version = paint(f"v{len(mr['versions'])}", DIM) if mr.get("versions") else paint("–", DIM)

    revs = []
    for rev in mr["reviewers"]["nodes"]:
        if rev["bot"]:
            continue
        state = (rev["mergeRequestInteraction"] or {}).get("reviewState")
        glyph, color = REVIEW.get(state, ("?", DIM))
        name = short(rev["username"], me)
        revs.append(paint(glyph, color) + paint(name, BOLD) if rev["username"] == me
                    else paint(glyph, color) + name)
    reviewers = " ".join(revs) or paint("none", RED)

    if mine:
        who = paint(fit("you: " + ", ".join(turn[me]), WHO_WIDTH), BOLD, YELLOW)
    elif turn:
        names = {u: "author" if u == author else short(u, me) for u in turn}
        who = paint(fit("; ".join(f"{names[u]}: {', '.join(r)}" for u, r in turn.items()),
                        WHO_WIDTH), CYAN)
    else:
        who = paint("–", DIM)

    iid = paint(f"!{mr['iid']}", BOLD if mine else BLUE)
    left = (f"{marker} {'  ' * depth}{pad(iid, 5)} {ci} {pad(talk, 5)} {pad(version, 6)} {pad(reviewers, 18)} "
            f"{pad(who, WHO_WIDTH)} {paint(age(mr['updatedAt']).rjust(3), DIM)}  ")
    width = int(os.environ.get("FZF_COLUMNS") or shutil.get_terminal_size((160, 40)).columns)
    room = max(20, width - visible_len(left))

    draft = "Draft " if mr["draft"] else ""
    by = f"  @{author}" if show_author and author != me else ""
    title = fit(mr["title"], room - len(draft) - len(by))
    return left + paint(draft, MAGENTA) + paint(title, *([] if involved else [DIM])) + paint(by, DIM)


WHO_WIDTH = 30


def fit(text, width):
    return text if len(text) <= width else text[:max(0, width - 1)] + "…"


def render(me, stacks, lines):
    """Append (text, url, project, iid) tuples, outgoing stacks then incoming."""
    groups = {"Outgoing": [], "Incoming": []}
    for stack in stacks:
        members = list(stack.walk())
        mine = any(stack.mrs[i]["author"]["username"] == me for i, _ in members)
        turns = {i: attention(stack.mrs[i], i == stack.root) for i, _ in members}
        groups["Outgoing" if mine else "Incoming"].append((stack, members, turns))

    for name, entries in groups.items():
        entries.sort(key=lambda e: (
            not any(me in t for t in e[2].values()),
            -max(parse_time(e[0].mrs[i]["updatedAt"]).timestamp() for i, _ in e[1])))
        lines.append((paint(f"{name} ({len(entries)})", BOLD, MAGENTA), "", "", ""))
        if not entries:
            lines.append((paint("  nothing here", DIM), "", "", ""))
        for stack, members, turns in entries:
            root = stack.mrs[stack.root]
            authors = sorted({stack.mrs[i]["author"]["username"] for i, _ in members})
            yours = sum(me in turns[i] for i, _ in members)
            head = (f"{stack.project.split('/')[-1]} → {root['targetBranch']}"
                    f" · {len(members)} MR{'s' * (len(members) > 1)}")
            if name == "Incoming":
                head += " · @" + ", @".join(authors)
            if yours:
                head += " · " + paint(f"your turn on {yours}", BOLD, YELLOW)
            lines.append(("", "", "", ""))
            lines.append(("  " + paint(head, BOLD), root["webUrl"], stack.project, root["iid"]))
            # Tip on top, like Gerrit's relation chain.
            for iid, depth in reversed(members):
                mr = stack.mrs[iid]
                lines.append((row(mr, depth, turns[iid], me, len(authors) > 1),
                              mr["webUrl"], stack.project, iid))
        lines.append(("", "", "", ""))


def collect():
    me, projects = fetch_me()
    stacks = []
    for project in projects:
        found = find_stacks(project, fetch_open(project), me)
        iids = sorted({i for s in found for i, _ in s.walk()}, key=int)
        details = fetch_details(project, iids) if iids else {}
        for stack in found:
            stack.mrs = details
        stacks += found
    lines = []
    render(me, stacks, lines)
    return lines


def legend():
    return paint("▶ your turn   CI ✔✘●○   threads unresolved/total   "
                 "v3→5 new code since you acted, v3≈5 only rebased   "
                 "reviewers ✔approved ✘changes ✎reviewed …in review ◌pending", DIM)


# --- Review worktrees --------------------------------------------------------

def run(*cmd, cwd=None, check=True, input=None):
    return subprocess.run(cmd, cwd=cwd, check=check, capture_output=True, text=True,
                          input=input).stdout.strip()


def herdr(*args):
    return json.loads(run("herdr", *args))["result"]


def local_repo(project):
    """The checkout of the project among the repos open in herdr, or the one we are in."""
    roots = {ws["worktree"]["repo_root"] for ws in herdr("workspace", "list")["workspaces"]
             if ws.get("worktree")}
    common = run("git", "rev-parse", "--path-format=absolute", "--git-common-dir", check=False)
    if common:
        roots.add(os.path.dirname(common))
    for root in sorted(roots):
        url = run("git", "-C", root, "remote", "get-url", "origin", check=False)
        if url.removesuffix(".git").endswith(("/" + project, ":" + project)):
            return root
    sys.exit(f"mr-dash: no herdr workspace has a checkout of {project}")


def change_id(repo, rev):
    return run("git", "-C", repo, "log", "-1", "--format=%(trailers:key=Change-Id,valueonly)", rev)


def safe_to_move(repo, old, new):
    """Whether moving from commit <old> to <new> only drops older versions of the merge request."""
    if old == new:
        return True
    ident = change_id(repo, new)
    if ident and change_id(repo, old) == ident:
        return True
    return subprocess.run(["git", "-C", repo, "merge-base", "--is-ancestor", old, new]).returncode == 0


def worktree(project, iid):
    """Open a herdr workspace on a worktree of the merge request's head, under its repo.

    Returns whether there is a message for the user to read.
    """
    repo = local_repo(project)
    mr = json.loads(run("glab", "api", f"projects/{project.replace('/', '%2F')}/merge_requests/{iid}"))
    print(f"Fetching !{iid} {mr['title']}")
    run("git", "-C", repo, "fetch", "--quiet", "origin", f"refs/merge-requests/{iid}/head")
    sha = run("git", "-C", repo, "rev-parse", "FETCH_HEAD")
    branch = f"mr/{iid}"
    label = fit(f"!{iid} {mr['title']}", 40)

    trees = herdr("worktree", "list", "--cwd", repo)["worktrees"]
    tree = next((t for t in trees if t.get("branch") == branch), None)
    if tree is None:
        if run("git", "-C", repo, "branch", "--list", branch):
            # Left behind by a removed worktree.
            if not safe_to_move(repo, branch, sha):
                sys.exit(f"mr-dash: branch {branch} has commits of its own; delete or rename it first")
            run("git", "-C", repo, "branch", "-D", branch)
        herdr("worktree", "create", "--cwd", repo, "--branch", branch, "--base", sha,
              "--label", label, "--focus")
        return False

    path = tree["path"]
    head = run("git", "-C", path, "rev-parse", "HEAD")
    kept = None
    if head == sha:
        pass
    elif run("git", "-C", path, "status", "--porcelain", "--untracked-files=no"):
        kept = "it has uncommitted changes"
    elif not safe_to_move(path, head, sha):
        kept = "it has commits of its own"
    else:
        run("git", "-C", path, "reset", "--quiet", "--hard", sha)
    if kept:
        print(f"Left {path} at {head[:10]}, not the latest {sha[:10]}: {kept}")
    if tree.get("open_workspace_id"):
        herdr("workspace", "focus", tree["open_workspace_id"])
    else:
        herdr("worktree", "open", "--cwd", repo, "--path", path, "--label", label, "--focus")
    return kept is not None


def interdiff(project, iid):
    """Page through what changed in the merge request since you last acted on it, or in
    its last push. Like Gerrit, the old version is first rebased onto the new base, so
    changes in the stack below don't show up."""
    me = graphql("query { currentUser { username } }")["currentUser"]["username"]
    mr = fetch_details(project, [iid])[iid]
    versions = mr["versions"]
    if len(versions) < 2:
        sys.exit(f"mr-dash: !{iid} has only been pushed once")
    seen, latest, _ = patchsets(mr, last_activity(mr).get(me))
    if not 0 < seen < latest:
        seen = latest - 1
    old, new = versions[seen - 1], versions[-1]

    repo = local_repo(project)
    run("git", "-C", repo, "fetch", "--quiet", "origin", old["base"], old["head"], new["base"], new["head"])
    note = "only rebased" if old["patch"] == new["patch"] else "code changed"
    header = paint(f"!{iid} {mr['title']}\nv{seen} → v{latest} ({note})", BOLD)
    rebased = subprocess.run(
        ["git", "-C", repo, "merge-tree", "--write-tree", f"--merge-base={old['base']}",
         new["base"], old["head"]], capture_output=True, text=True)
    if rebased.returncode == 0:
        diff = run("git", "-C", repo, "diff", "--no-color", rebased.stdout.split()[0], new["head"])
        diff = highlight(diff) if diff else paint("No changes besides the rebase.", DIM)
    else:
        # The stack below touched the same lines; compare the two patches instead.
        header += paint(" · the rebase conflicts, so this is a range-diff", DIM)
        diff = run("git", "-C", repo, "range-diff", "--color=always" if COLOR else "--no-color",
                   f"{old['base']}..{old['head']}", f"{new['base']}..{new['head']}")
    # Stay open even when it fits on the screen, or fzf draws over it at once.
    pager = os.environ.get("PAGER") or "less"
    subprocess.run(shlex.split(pager) + (["-R", "-+F"] if pager == "less" else []),
                   input=f"{header}\n\n{diff}\n", text=True)


def highlight(diff):
    """The diff syntax highlighted by delta, when it is around."""
    if not COLOR or not shutil.which("delta"):
        return diff
    width = shutil.get_terminal_size((160, 40)).columns
    return run("delta", "--paging=never", f"--width={width}", input=diff)


def nit_push(project, iid):
    """Push every version of the merge request to nit, from its worktree, so nit holds
    them all as revisions. The merge requests below it come along in the order they
    were pushed, since nit takes the whole chain each time. Returns True: there is a
    summary to read."""
    repo = local_repo(project)
    trees = herdr("worktree", "list", "--cwd", repo)["worktrees"]
    tree = next((t for t in trees if t.get("branch") == f"mr/{iid}"), None)
    if tree is None:
        sys.exit(f"mr-dash: !{iid} has no worktree yet; make one with alt-w first")

    by_source = {mr["sourceBranch"]: mr for mr in fetch_open(project)}
    by_iid = {mr["iid"]: mr for mr in by_source.values()}
    # Forget merge requests that were merged or closed, so their commits can go.
    for ref in run("git", "-C", repo, "for-each-ref", "--format=%(refname)", NIT_REF).split():
        if ref.removeprefix(NIT_REF) not in by_iid:
            run("git", "-C", repo, "update-ref", "-d", ref)
    chain, mr = [], by_iid.get(iid)
    while mr and mr["iid"] not in chain:
        chain.append(mr["iid"])
        mr = by_source.get(mr["targetBranch"])
    with ThreadPoolExecutor(max_workers=16) as pool:
        versions = dict(zip(chain, pool.map(lambda i: fetch_versions(project, i), chain)))

    # Resume after the newest version nit got from the chain, so no change in it
    # goes back to an older revision.
    since = None
    for i in chain:
        done = run("git", "-C", repo, "rev-parse", "--verify", "--quiet", NIT_REF + i, check=False)
        for v in versions[i]:
            if v["head"] == done and (since is None or v["created"] > since):
                since = v["created"]
    todo = sorted((v["created"], int(i), v["head"]) for i in chain for v in versions[i]
                  if since is None or v["created"] > since)
    if not todo:
        print(f"nit already has every version of !{iid}")
        return True

    run("git", "-C", repo, "fetch", "--quiet", "origin", *{head for *_, head in todo})
    for n, (created, i, head) in enumerate(todo, 1):
        print(f"[{n}/{len(todo)}] !{i} at {head[:10]}, pushed {age(created.isoformat())} ago")
        subprocess.run(["nit", "push", head], cwd=tree["path"], check=True,
                       stdout=subprocess.DEVNULL, stderr=subprocess.PIPE, text=True)
        run("git", "-C", repo, "update-ref", NIT_REF + str(i), head)
    print(f"Pushed {len(todo)} versions of !{iid} and the {len(chain) - 1} MRs below it to nit")
    return True


NIT_REF = "refs/mr-dash/nit/"  # the version of each merge request nit got last


# --- Preview -----------------------------------------------------------------

def preview(project, iid):
    """The merge request as the preview pane shows it: description, then open threads,
    plain comments and resolved threads, each note marked by who wrote it."""
    data = graphql(f"""
      query {{
        currentUser {{ username }}
        project(fullPath: {json.dumps(project)}) {{
          mergeRequest(iid: {json.dumps(iid)}) {{
            iid title description draft sourceBranch targetBranch
            author {{ username }}
            headPipeline {{ status }}
            reviewers {{ nodes {{ username bot mergeRequestInteraction {{ reviewState }} }} }}
            discussions(first: 100) {{
              nodes {{
                resolvable resolved
                notes(first: 100) {{
                  nodes {{
                    system body createdAt
                    author {{ username bot }}
                    position {{ filePath newLine oldLine }}
                  }}
                }}
              }}
            }}
          }}
        }}
      }}""")
    me, mr = data["currentUser"]["username"], data["project"]["mergeRequest"]
    # One column short, so the scrollbar doesn't wrap the rules.
    width = int(os.environ.get("FZF_PREVIEW_COLUMNS") or shutil.get_terminal_size((100, 40)).columns) - 1

    # push-stack's change/<Change-Id> branches: the Change-Id's start tells them apart.
    def branch(name):
        return fit(name, 17) if name.startswith("change/") else name
    glyph, color = CI.get((mr["headPipeline"] or {}).get("status"), ("–", DIM))
    revs = []
    for rev in mr["reviewers"]["nodes"]:
        if not rev["bot"]:
            mark, mark_color = REVIEW.get((rev["mergeRequestInteraction"] or {}).get("reviewState"), ("?", DIM))
            revs.append(paint(mark, mark_color) + who(rev["username"], me))
    out = [paint(("Draft: " if mr["draft"] else "") + f"!{mr['iid']} {mr['title']}", BOLD),
           paint(f"@{mr['author']['username']} · {branch(mr['sourceBranch'])} → {branch(mr['targetBranch'])} · CI ", DIM)
           + paint(glyph, color) + paint(" · reviewers ", DIM) + (" ".join(revs) or paint("none", RED)),
           ""]
    out += [paint(line, DIM) if line.startswith("Change-Id:") else line
            for line in markdown(mr["description"] or "", width)]

    threads, comments, resolved = [], [], []
    for disc in mr["discussions"]["nodes"]:
        notes = [n for n in disc["notes"]["nodes"] if not n["system"]]
        if notes:
            (resolved if disc["resolved"] else threads if disc["resolvable"] else comments).append(notes)

    if threads:
        out += ["", paint(f"Open threads ({len(threads)})", BOLD, MAGENTA)]
        for notes in threads:
            out += ["", rule(f"● {where(notes[0], width - 8)}", YELLOW, width)]
            for n, note in enumerate(notes):
                out += note_lines(note, me, width, "  " * (n > 0))
    if comments:
        out += ["", paint(f"Comments ({len(comments)})", BOLD, MAGENTA)]
        for notes in comments:
            out.append("")
            for note in notes:
                out += note_lines(note, me, width, "")
    if resolved:
        # Folded to a line each: settled, so only there to look up.
        out += ["", paint(f"Resolved threads ({len(resolved)})", BOLD, MAGENTA), ""]
        for notes in resolved:
            head = paint(f"✔ {where(notes[0], width // 3)}", GREEN)
            author = notes[0]["author"]
            name = who(author["username"], me, author["bot"])
            replies = f" +{len(notes) - 1}" if len(notes) > 1 else ""
            room = width - visible_len(head) - visible_len(name) - len(replies) - 4
            text = fit(" ".join(notes[0]["body"].split()), max(10, room))
            out.append(f"{head}  {name}{paint(': ' + text + replies, DIM)}")
    print("\n".join(out))


def who(user, me, bot=False):
    """The author's name, green for you and dim for bots, so you can tell notes apart."""
    return paint("you", BOLD, GREEN) if user == me else paint(user, DIM) if bot else paint(user, BOLD, CYAN)


def where(note, width):
    """Where the note is, as path:line; the path loses directories from the front to fit."""
    pos = note["position"]
    if not pos:
        return "on the merge request"
    line = f":{pos['newLine'] or pos['oldLine']}"
    parts = pos["filePath"].split("/")
    while len(parts) > 1 and len("/".join(parts)) + len(line) > width:
        parts = parts[1:] if parts[0] == "…" else ["…"] + parts[2:] if len(parts) > 2 else parts[1:]
    return "/".join(parts) + line


def rule(title, color, width):
    title = fit(title, width - 4)
    return paint(f"── {title} " + "─" * max(0, width - len(title) - 4), color)


def note_lines(note, me, width, indent):
    """The note under a header, behind a bar in its author's colour."""
    user, bot = note["author"]["username"], note["author"]["bot"]
    color = GREEN if user == me else DIM if bot else CYAN
    bar = indent + paint("▌", color) + " "
    lines = [bar + who(user, me, bot) + paint(f" · {age(note['createdAt'])} ago", DIM)]
    lines += [bar + line for line in markdown(note["body"], width - len(indent) - 2)]
    return lines


def markdown(text, width):
    """The text wrapped to <width>, with code set apart: inline in yellow, fenced blocks
    unwrapped between dim corners."""
    lines, fence, blank = [], False, False
    for raw in text.strip().splitlines():
        stripped = raw.strip()
        if stripped.startswith("```"):
            label = stripped[3:].split(":")[0]
            lines.append(paint(("└" if fence else "┌ " + label).rstrip(), DIM))
            fence, blank = not fence, False
            continue
        if fence:
            lines.append(paint(raw, YELLOW))
            continue
        if not stripped:
            if not blank:
                lines.append("")
            blank = True
            continue
        blank = False
        bullet = re.match(r"\s*([-*+]|\d+[.)])\s+", raw)
        hang = " " * (bullet.end() if bullet else len(raw) - len(raw.lstrip()))
        for line in textwrap.wrap(raw, width, subsequent_indent=hang, break_on_hyphens=False) or [""]:
            lines.append(re.sub(r"`([^`]+)`", lambda m: paint(m[1], YELLOW), line))
    return lines


def interactive():
    self_cmd = shlex.join([sys.executable, os.path.abspath(sys.argv[0])])
    preview = f"[ -n {{4}} ] && {self_cmd} --preview {{3}} {{4}}"
    fzf = subprocess.Popen(
        ["fzf", "--ansi", "--no-sort", "--layout=reverse", "--delimiter=\t",
         "--with-nth=1", "--info=hidden", "--no-separator", "--header-first",
         f"--header={legend()}\n"
         "enter: open in browser · alt-d: diff since you acted · alt-w: herdr worktree"
         " · alt-n: push to nit"
         " · ctrl-r: reload · ?: preview",
         "--preview", preview, "--preview-window=down,60%,hidden,wrap",
         "--bind", "?:toggle-preview",
         "--bind", f"ctrl-r:reload({self_cmd} --lines)",
         "--bind", "enter:execute-silent([ -n {2} ] && xdg-open {2})",
         "--bind", f"alt-w:execute([ -n {{4}} ] && {self_cmd} --worktree {{3}} {{4}} --pause-on-error)",
         "--bind", f"alt-d:execute([ -n {{4}} ] && {self_cmd} --interdiff {{3}} {{4}} --pause-on-error)",
         "--bind", f"alt-n:execute([ -n {{4}} ] && {self_cmd} --nit {{3}} {{4}} --pause-on-error)"],
        stdin=subprocess.PIPE, text=True,
    )
    for line in collect():
        fzf.stdin.write("\t".join(line) + "\n")
    fzf.stdin.close()
    fzf.wait()


def main():
    global COLOR
    parser = argparse.ArgumentParser(
        description="Gerrit-like dashboard of your GitLab merge request stacks.")
    parser.add_argument("-i", "--interactive", action="store_true",
                        help="browse the dashboard in fzf")
    parser.add_argument("--worktree", nargs=2, metavar=("PROJECT", "IID"),
                        help="review the merge request in a herdr worktree")
    parser.add_argument("--interdiff", nargs=2, metavar=("PROJECT", "IID"),
                        help="show what changed since you last acted on the merge request")
    parser.add_argument("--nit", nargs=2, metavar=("PROJECT", "IID"),
                        help="push every version of the merge request to nit, from its worktree")
    parser.add_argument("--lines", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--preview", nargs=2, help=argparse.SUPPRESS)
    parser.add_argument("--pause-on-error", action="store_true", help=argparse.SUPPRESS)
    args = parser.parse_args()

    if args.worktree or args.interdiff or args.nit:
        try:
            if args.worktree:
                notice = worktree(*args.worktree)
            elif args.nit:
                notice = nit_push(*args.nit)
            else:
                notice = interdiff(*args.interdiff)
            if notice and args.pause_on_error:
                input("Press enter to go back")
        except (SystemExit, subprocess.CalledProcessError) as err:
            if isinstance(err, subprocess.CalledProcessError):
                print(f"mr-dash: {' '.join(err.cmd)} failed:\n{err.stderr.strip()}", file=sys.stderr)
            elif err.code in (None, 0):
                return
            else:
                print(err.code, file=sys.stderr)
            if args.pause_on_error:
                input("Press enter to go back")
            sys.exit(1)
        return

    if args.interactive or args.lines or args.preview:
        COLOR = "NO_COLOR" not in os.environ
    if args.preview:
        preview(*args.preview)
    elif args.interactive:
        interactive()
    elif args.lines:
        for line in collect():
            print("\t".join(line))
    else:
        print(legend())
        print()
        for text, *_ in collect():
            print(text)


if __name__ == "__main__":
    main()
