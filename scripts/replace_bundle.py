#!/usr/bin/env python3
"""Publish a staged app on the same filesystem without merging its contents."""
import ctypes
import os
from pathlib import Path
import sys


def replace(staged, live):
    if live.is_symlink():
        raise ValueError("Refusing to replace an app symlink.")
    if not live.exists():
        staged.rename(live)
        return
    # RENAME_SWAP atomically exchanges the two directory names.
    rename = ctypes.CDLL(None, use_errno=True).renamex_np
    rename.argtypes = (ctypes.c_char_p, ctypes.c_char_p, ctypes.c_uint)
    rename.restype = ctypes.c_int
    if rename(os.fsencode(staged), os.fsencode(live), 0x00000002) != 0:
        error = ctypes.get_errno()
        raise OSError(error, os.strerror(error))


if __name__ == "__main__":
    replace(Path(sys.argv[1]), Path(sys.argv[2]))
