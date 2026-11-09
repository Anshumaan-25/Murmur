"""Apply the bounded private-input adapter to the exact pinned scratch source."""
from pathlib import Path
import shutil


def patch_speech(source, root):
    def replace(path, before, after):
        code = path.read_text()
        if code.count(before) != 1:
            raise SystemExit(f"Recheck the private speech adapter at {path.name}: {before[:70]!r}")
        path.write_text(code.replace(before, after))

    cli = source / "examples/cli/cli.cpp"
    shutil.copyfile(root / "helpers/keydown_request.h", cli.parent / "keydown_request.h")
    replace(cli, '#include "whisper.h"', '#include "whisper.h"\n#include "keydown_request.h"')
    replace(cli, '    std::string prompt;', '    std::string prompt;\n    bool keydown_protocol = false;\n    size_t keydown_audio_bytes = 0;')
    replace(cli, '        else if (                  arg == "--prompt")',
            '        else if (arg == "--keydown-request-v1") { params.keydown_protocol = true; }\n        else if (                  arg == "--prompt")')
    replace(cli, '    // number of input files that could not be processed or whose output could not be written', '''    if (params.keydown_protocol) {
        keydown_request request;
        if (!params.prompt.empty() || params.fname_inp.size() != 1 || params.fname_inp[0] != "-" ||
            !keydown_read_request(stdin, request)) { return 65; }
        params.prompt = request.prompt;
        params.keydown_audio_bytes = request.audio_bytes;
    }
    // number of input files that could not be processed or whose output could not be written''')
    replace(cli, 'read_audio_data(fname_inp, pcmf32, pcmf32s, params.diarize)',
            'read_audio_data(fname_inp, pcmf32, pcmf32s, params.diarize, params.keydown_audio_bytes)')
    header = source / "examples/common-whisper.h"
    replace(header, 'const std::string & fname,\n        std::vector<float> & pcmf32,\n        std::vector<std::vector<float>> & pcmf32s,\n        bool stereo);', 'const std::string & fname,\n        std::vector<float> & pcmf32,\n        std::vector<std::vector<float>> & pcmf32s,\n        bool stereo, size_t expected_bytes = 0);')
    common = source / "examples/common-whisper.cpp"
    replace(common, 'bool read_audio_data(const std::string & fname, std::vector<float> & pcmf32, std::vector<std::vector<float>> & pcmf32s, bool stereo) {', 'bool read_audio_data(const std::string & fname, std::vector<float> & pcmf32, std::vector<std::vector<float>> & pcmf32s, bool stereo, size_t expected_bytes) {')
    replace(common, '            audio_data.insert(audio_data.end(), buf, buf + n);', '''            if (audio_data.size() + n > 19200044 ||
                (expected_bytes && audio_data.size() + n > expected_bytes)) return false;
            audio_data.insert(audio_data.end(), buf, buf + n);''')
    replace(common, '            audio_data.insert(audio_data.end(), buf, buf + n);\n        }', '''            audio_data.insert(audio_data.end(), buf, buf + n);
        }
        if (expected_bytes && audio_data.size() != expected_bytes) return false;''')
