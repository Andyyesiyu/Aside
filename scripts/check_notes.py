#!/usr/bin/env python3
"""Validate repository decision records; no third-party dependencies."""
import argparse
from datetime import date
from pathlib import Path
import re
import subprocess
from urllib.parse import unquote, urlsplit

STATES = {'proposed', 'implemented', 'rejected', 'archived'}
CATEGORIES = {'feature', 'bug-fix', 'architecture', 'process', 'testing', 'simplification'}
PROPOSAL = ['Problem', 'Proposal', 'Alternatives considered', 'Acceptance criteria', 'Risks']
IMPLEMENTED = ['Problem', 'Decision', 'Alternatives considered', 'Consequences', 'Verification']


def git(root, *args):
    return subprocess.check_output(['git', '-C', str(root), *args], stderr=subprocess.PIPE)


def active_note(name):
    parts = Path(name).parts
    return len(parts) == 5 and parts[:2] == ('.agents', 'notes') and parts[2] in STATES - {'archived'} and parts[3] in CATEGORIES and parts[4] not in {'README.md', 'AGENTS.md'} and parts[4].endswith('.md')


def validate(root, base=None):
    root = Path(root).resolve()
    errors = []
    notes = root / '.agents/notes'
    if not notes.is_dir():
        return ['missing .agents/notes directory']
    for path in sorted(notes.rglob('*.md')):
        rel = path.relative_to(notes)
        if path.name in {'README.md', 'AGENTS.md'}:
            continue
        parts = rel.parts
        if len(parts) != 3 or parts[0] not in STATES or parts[1] not in CATEGORIES or not re.fullmatch(r'\d{4}-\d{2}-\d{2}-[a-z0-9]+(?:-[a-z0-9]+)*\.md', path.name):
            errors.append(f'{rel}: invalid note path')
            continue
        try:
            date.fromisoformat(path.name[:10])
        except ValueError:
            errors.append(f'{rel}: invalid date')
        text = path.read_text()
        lines = text.splitlines()
        expected = 'implemented' if parts[0] == 'archived' else parts[0]
        status = re.search(r'^Status: (.+)$', text, re.M)
        value = status.group(1) if status else ''
        good_status = bool(re.fullmatch(r'rejected — \S.*', value)) if expected == 'rejected' else value == expected
        if not good_status or len(lines) < 3 or not lines[0].startswith('# ') or lines[1] != '' or not lines[2].startswith('Status: '):
            errors.append(f'{rel}: invalid header or status')
        if parts[0] == 'archived':
            archived = re.search(r'^Archived: (\d{4}-\d{2}-\d{2})$', text, re.M)
            try:
                date.fromisoformat(archived.group(1) if archived else '')
            except ValueError:
                errors.append(f'{rel}: missing or invalid Archived date')
        required = IMPLEMENTED if expected == 'implemented' else PROPOSAL
        for heading in required:
            section = re.search(r'^## '+re.escape(heading)+r'\s*\n(.*?)(?=^## |\Z)', text, re.M | re.S)
            if not section or not section.group(1).strip():
                errors.append(f'{rel}: missing or empty section {heading}')
    documents = list(notes.rglob('*.md')) + list((root / 'docs').rglob('*.md')) + list((root / '.agents/templates').rglob('*.md'))
    documents += [root / name for name in ('AGENTS.md', 'README.md', 'GITHUB_SETUP.md') if (root / name).exists()]
    for path in documents:
        # Frozen archives can retain historical links to files that no longer exist.
        if '.agents/notes/archived/' in path.relative_to(root).as_posix():
            continue
        text = re.sub(r'^```.*?^```[^\n]*', '', path.read_text(), flags=re.M | re.S)
        for target in re.findall(r'\[[^\]\n]*\]\(([^)\n]+)\)', text):
            target = target.strip().strip('<>')
            parsed = urlsplit(target)
            if parsed.scheme or target.startswith(('#', '//')) or not parsed.path:
                continue
            dest = (path.parent / unquote(parsed.path)).resolve()
            if not dest.is_relative_to(root) or not dest.exists():
                errors.append(f'{path.relative_to(root)}: broken local link {target}')
    if base:
        try:
            base = git(root, 'rev-parse', '--verify', base + '^{commit}').decode().strip()
            frozen = git(root, 'ls-tree', '-r', '--name-only', '-z', base, '--', '.agents/notes/archived').decode().split('\0')
            for name in filter(None, frozen):
                path = root / name
                if not path.is_file() or path.read_bytes() != git(root, 'show', base + ':' + name):
                    errors.append(f'{name}: frozen archive changed or deleted')
            changed = set(filter(None, git(root, 'diff', '--name-only', '-z', base, '--').decode().split('\0')))
            changed.update(filter(None, git(root, 'ls-files', '--others', '--exclude-standard', '-z').decode().split('\0')))
            significant = any(n.startswith(('Sources/', 'scripts/', '.github/workflows/')) or n in {'build.sh', 'Info.plist'} for n in changed)
            if significant and not any(active_note(n) and (root / n).is_file() for n in changed):
                errors.append('code/process change requires an added or updated active note')
        except subprocess.CalledProcessError as exc:
            errors.append('cannot check Git baseline: ' + exc.stderr.decode().strip())
    return errors


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', help='Git baseline for archive and change checks')
    args = parser.parse_args()
    errors = validate(Path(__file__).resolve().parents[1], args.base)
    if errors:
        print('\n'.join(errors))
        return 1
    print('Agent Notes checks passed' + (' (including Git baseline)' if args.base else ''))
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
