"""Read the worker roles this plugin ships, from its own agents/ folder.

The role files are the single source: a role's `description` says what it is
for, and its `effort` is what a spawned session should run at. Keeping a copy
of either here would drift the first time a role changed, and nothing would
notice, because the copy would still print.

The plugin root is found from this file's own location rather than from
CLAUDE_SKILL_DIR, so it resolves the same way from the plugin cache and from a
checkout loaded with --plugin-dir.

  roles.py list           every role, namespaced, with its effort and description
  roles.py effort <role>  that role's effort, or nothing if it sets none or is
                          not one of this plugin's roles
"""
import json
import pathlib
import re
import sys

ROOT = pathlib.Path(__file__).resolve().parents[3]
KEY = re.compile(r'^([A-Za-z][\w-]*):\s*(.*)$')
BLOCK = {'>', '>-', '|', '|-'}


def frontmatter(path):
    """Top-level keys of a YAML frontmatter block: plain scalars and the
    folded or literal blocks the role files use. Enough for these files, not a
    YAML parser."""
    lines = path.read_text(encoding='utf-8').splitlines()
    if not lines or lines[0].strip() != '---':
        return {}
    fields, key, block = {}, None, []
    for line in lines[1:]:
        if line.strip() == '---':
            break
        m = KEY.match(line)
        if m:
            if key is not None:
                fields[key] = ' '.join(block)
            key, value = m.group(1), m.group(2).strip()
            if value in BLOCK:
                block = []
            else:
                fields[key], key = value.strip('\'"'), None
        elif key is not None and line.strip():
            block.append(line.strip())
    if key is not None:
        fields[key] = ' '.join(block)
    return fields


def roles():
    manifest = ROOT / '.claude-plugin' / 'plugin.json'
    try:
        plugin = json.loads(manifest.read_text(encoding='utf-8'))['name']
    except (OSError, ValueError, KeyError) as e:
        sys.exit(f'cannot read the plugin name from {manifest}: {e}')
    found = []
    for path in sorted((ROOT / 'agents').glob('*.md')):
        fields = frontmatter(path)
        name = fields.get('name') or path.stem
        found.append((f'{plugin}:{name}', fields))
    return found


def main(argv):
    if argv[:1] == ['list'] and len(argv) == 1:
        found = roles()
        if not found:
            sys.exit(f'no roles found in {ROOT / "agents"}')
        for role, fields in found:
            print(f'{role}  (effort: {fields.get("effort") or "default"})')
            print(f'  {fields.get("description", "(no description)")}')
            print()
        return
    if argv[:1] == ['effort'] and len(argv) == 2:
        for role, fields in roles():
            if role == argv[1] and fields.get('effort'):
                print(fields['effort'])
        return
    sys.exit('usage: roles.py list | roles.py effort <role>')


if __name__ == '__main__':
    main(sys.argv[1:])
