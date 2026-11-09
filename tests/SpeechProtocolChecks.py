"""Exercise the actual C++ request parser with hostile synthetic input."""
from pathlib import Path
import struct
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class SpeechProtocolChecks(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.work = tempfile.TemporaryDirectory(prefix="keydown-protocol-test-")
        root = Path(cls.work.name)
        source = root / "probe.cpp"
        source.write_text('''#include "keydown_request.h"
int main() {
    keydown_request request;
    if (!keydown_read_request(stdin, request)) return 2;
    unsigned count = 0;
    while (fgetc(stdin) != EOF) { if (++count > request.audio_bytes) return 3; }
    if (count != request.audio_bytes) return 3;
    printf("%s", request.prompt.c_str());
}
''')
        cls.binary = root / "probe"
        subprocess.run(["/usr/bin/clang++", "-std=c++11", "-I", str(ROOT / "helpers"),
                        str(source), "-o", str(cls.binary)], check=True, capture_output=True)

    @classmethod
    def tearDownClass(cls):
        cls.work.cleanup()

    def run_request(self, prompt=b"PostgreSQL", audio=b"fixture", version=1, size=None):
        header = b"KDSP" + struct.pack("<III", version, len(prompt), len(audio) if size is None else size)
        return subprocess.run([self.binary], input=header + prompt + audio, capture_output=True, timeout=2)

    def test_unicode_vocabulary_and_audio(self):
        result = self.run_request("Siobhán, PostgreSQL".encode())
        self.assertEqual(result.returncode, 0)
        self.assertEqual(result.stdout.decode(), "Siobhán, PostgreSQL")

    def test_version_and_bounds(self):
        for args in [dict(version=2), dict(prompt=b"x" * 4097), dict(size=19200045), dict(size=0)]:
            self.assertNotEqual(self.run_request(**args).returncode, 0)

    def test_invalid_text_and_lengths(self):
        for args in [dict(prompt=b"bad\0term"), dict(prompt=b"bad\nterm"), dict(prompt=b"\xff"),
                     dict(prompt=b"\xc0\x80"), dict(prompt=b"\xed\xa0\x80"), dict(size=3), dict(size=10)]:
            self.assertNotEqual(self.run_request(**args).returncode, 0)

    def test_truncated_header(self):
        result = subprocess.run([self.binary], input=b"KDSP", capture_output=True, timeout=2)
        self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
