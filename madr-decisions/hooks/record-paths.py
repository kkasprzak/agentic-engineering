"""Pick the decision records a tool call is about to write.

Reads the harness's PreToolUse JSON on stdin. Prints the session's working
directory on the first line, then one candidate path per line.

This lives in its own file rather than inside `python3 -c '...'` in the hook,
because the shell's single quotes cannot hold the apostrophes this code needs
and escaping them turns the logic into noise. It is also one interpreter launch
instead of three.

For `Edit` and `Write` the answer is given: `tool_input.file_path`.

For `Bash` there is no target, only a command string, and whether that string
writes a given file cannot be decided in general. So the question asked here is
narrower: is this record the *target* of a write in this command. The first
version asked the wider one and refused `grep status 0014-x.md 2>/dev/null`,
because `2>` is a redirect and the record was named somewhere in the line. A
guard which blocks reading is a guard somebody turns off, and then it protects
nothing at all.
"""

import json
import re
import sys

EDITORS = {"sed", "gsed", "perl", "ruby", "awk", "gawk"}
LINE_EDITORS = {"ed", "ex"}
COPIERS = {"cp", "mv", "install", "rsync"}

IN_PLACE = re.compile(
    r"(?:^|\s)(?:--in-place\b|-[A-Za-z]*[iI][A-Za-z]*\b|-i[ =]inplace\b)"
)
PY_WRITE = re.compile(r"""open\([^)]*["'][wa]""")
PATH_RE = re.compile(r"""[^\s"'<>|;&()]*\b[0-9]{4}-[^\s"'<>|;&()]*\.md""")
ASSIGNMENT = re.compile(r"^[A-Za-z_]\w*=")


def mask(text):
    """Blank the inside of quoted spans, keeping every offset where it was.

    Without this the `;` inside `sed -i 's/a/b/;s/c/d/' record.md` reads as a
    command separator, the `sed` falls outside the simple command being
    examined, and the write goes through. That included
    `sed -i '/^status:/{s/proposed/accepted/;}' record.md`, which is the exact
    edit this plugin exists to refuse.
    """
    out, quote = [], None
    for ch in text:
        if quote:
            out.append(ch if ch == quote else "x")
            if ch == quote:
                quote = None
        elif ch in "\"'":
            quote = ch
            out.append(ch)
        else:
            out.append(ch)
    return "".join(out)


def simple_command(masked, at):
    """The text of the command containing `at`, and the command's name."""
    cut = max(masked.rfind(c, 0, at) for c in "|;&\n")
    segment = masked[cut + 1:at]
    # Skip leading environment assignments, then take the command word. Anchored
    # like this so `grep -n ex record.md` is not read as the `ex` editor.
    m = re.match(r"\s*(?:[A-Za-z_]\w*=\S*\s+)*([\w./-]+)", segment)
    name = m.group(1).rsplit("/", 1)[-1] if m else ""
    return segment, name


def writes(masked, raw_cmd, path, at):
    before = masked[:at]

    # An input redirect means the record is being read, not written.
    if re.search(r"<\s*$", before):
        return False

    # An output redirect right in front of it names it as the target, whatever
    # file descriptor is attached. `echo x 2> record` truncates the record just
    # as surely as `> record` does.
    if re.search(r">>?\s*$", before):
        return True

    segment, name = simple_command(masked, at)

    if name in LINE_EDITORS:
        return True
    if name in EDITORS and IN_PLACE.search(segment):
        return True
    if name == "tee":
        return True
    if name in COPIERS:
        # Only the destination is written, and that is the last operand.
        rest = masked[at + len(path):]
        # `\d*` before the redirect, or `cp x record 2>/dev/null` leaves a bare
        # "2" behind and the destination stops looking like the last operand.
        rest = re.split(r"[|;&\n#]|\d*>>?|<", rest)[0]
        if not rest.strip():
            return True
    # Searched in the raw command, not the masked one: a python one-liner lives
    # entirely inside the shell's quotes, so masking blanks the very thing this
    # is looking for. Working out which argument it opens would mean parsing
    # python, so the test stays coarse — the command opens something for writing
    # and it names this record.
    if PY_WRITE.search(raw_cmd):
        return True
    return False


def cd_prefixes(masked):
    """Directories the command moved into, composed left to right.

    `cd docs && cd adr && sed -i ... 0014-x.md` leaves the filename relative to
    a directory the hook is not standing in.
    """
    prefixes, acc = [""], ""
    for d in re.findall(r"\bcd\s+([^\s;&|]+)", masked):
        d = d.strip("\"' ")
        acc = d if d.startswith("/") else (acc.rstrip("/") + "/" + d if acc else d)
        prefixes.append(acc)
    return prefixes


def bash_candidates(cmd):
    masked = mask(cmd)
    prefixes = cd_prefixes(masked)
    for m in PATH_RE.finditer(cmd):
        raw = m.group(0)
        if not writes(masked, cmd, raw, m.start()):
            continue
        # `F=docs/adr/0014-x.md` matches with the assignment glued on. Strip it
        # so the candidate is the path and not the whole word.
        cand = ASSIGNMENT.sub("", raw)
        yield cand
        if not cand.startswith("/"):
            for prefix in prefixes:
                if prefix:
                    yield prefix.rstrip("/") + "/" + cand


def main():
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0

    print(payload.get("cwd", ""))

    tool = payload.get("tool_name", "")
    tool_input = payload.get("tool_input") or {}

    if tool == "Bash":
        for candidate in bash_candidates(tool_input.get("command", "") or ""):
            print(candidate)
    else:
        path = tool_input.get("file_path", "")
        if path:
            print(path)
    return 0


if __name__ == "__main__":
    sys.exit(main())
