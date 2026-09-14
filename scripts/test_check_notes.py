import subprocess
import tempfile
from pathlib import Path
import unittest
from check_notes import validate

BODY = '# Agent Note: Example\n\nStatus: implemented\n' + ''.join('\n## '+h+'\n\nEvidence.\n' for h in ['Problem', 'Decision', 'Alternatives considered', 'Consequences', 'Verification'])


class NotesTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.root = Path(self.tmp.name)
        self.note = self.write('.agents/notes/implemented/process/2026-09-14-example.md', BODY)

    def write(self, name, body):
        p = self.root / name
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(body)
        return p

    def git(self, *args):
        return subprocess.check_output(['git', '-C', str(self.root), *args], stderr=subprocess.PIPE).decode().strip()

    def baseline(self):
        self.git('init')
        self.git('add', '.')
        self.git('-c', 'user.name=Test', '-c', 'user.email=test@example.invalid', '-c', 'core.hooksPath=/dev/null', 'commit', '-m', 'fixture')
        return self.git('rev-parse', 'HEAD')

    def test_valid(self):
        self.assertEqual(validate(self.root), [])

    def test_bad_status(self):
        self.note.write_text(BODY.replace('Status: implemented', 'Status: proposed'))
        self.assertTrue(any('status' in e for e in validate(self.root)))

    def test_missing_section(self):
        self.note.write_text(BODY.replace('## Alternatives considered', '## Other'))
        self.assertTrue(any('Alternatives considered' in e for e in validate(self.root)))

    def test_broken_link(self):
        self.note.write_text(BODY + '\n[missing](missing.md)\n')
        self.assertTrue(any('broken local link' in e for e in validate(self.root)))

    def test_category(self):
        self.write('.agents/notes/implemented/unknown/2026-09-14-invalid.md', BODY)
        self.assertTrue(any('invalid note path' in e for e in validate(self.root)))

    def test_archive_freeze(self):
        p = self.write('.agents/notes/archived/process/2026-09-14-old.md', BODY.replace('Status: implemented', 'Status: implemented\nArchived: 2026-09-14'))
        base = self.baseline()
        self.assertEqual(validate(self.root, base), [])
        p.write_text(p.read_text() + '\nChanged\n')
        self.assertTrue(any('frozen archive' in e for e in validate(self.root, base)))
        p.unlink()
        self.assertTrue(any('frozen archive' in e for e in validate(self.root, base)))

    def test_change_gate_including_untracked(self):
        base = self.baseline()
        self.write('Sources/Example.swift', '// change\n')
        self.assertTrue(any('requires' in e for e in validate(self.root, base)))
        self.note.write_text(BODY + '\nUpdated verification.\n')
        self.assertEqual(validate(self.root, base), [])

    def test_invalid_baseline(self):
        self.baseline()
        self.assertTrue(any('baseline' in e for e in validate(self.root, 'missing-ref')))


if __name__ == '__main__':
    unittest.main()
