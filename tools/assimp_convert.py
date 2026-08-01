# -*- coding: utf-8 -*-
"""Convert meshes via Assimp C API (DLL) when Blender/FBX2glTF insufficient."""
from __future__ import annotations

import ctypes
from ctypes import c_char_p, c_uint, c_void_p, POINTER
from pathlib import Path

ASSIMP_DLL = Path(r"H:\game_dev\eveautochess-dev\tools\assimp\Release\assimp-vc143-mt.dll")


class AssimpError(RuntimeError):
    pass


def _load():
    if not ASSIMP_DLL.is_file():
        raise AssimpError(f"DLL missing: {ASSIMP_DLL}")
    dll = ctypes.CDLL(str(ASSIMP_DLL))
    dll.aiImportFile.argtypes = [c_char_p, c_uint]
    dll.aiImportFile.restype = c_void_p
    dll.aiReleaseImport.argtypes = [c_void_p]
    dll.aiReleaseImport.restype = None
    dll.aiGetErrorString.argtypes = []
    dll.aiGetErrorString.restype = c_char_p
    dll.aiExportScene.argtypes = [c_void_p, c_char_p, c_char_p, c_uint]
    dll.aiExportScene.restype = c_uint  # aiReturn
    return dll


# CalcTangentSpace | JoinIdenticalVertices | Triangulate | GenSmoothNormals |
# ImproveCacheLocality | FixInfacingNormals | SortByPType
# (0x1 alone is CalcTangentSpace — needs GenSmoothNormals=0x40 first for UV ships.)
FLAGS = 0x1 | 0x2 | 0x8 | 0x40 | 0x800 | 0x2000 | 0x8000


def convert(src: Path, dst: Path, format_id: str = "glb2") -> None:
    """format_id: glb2, gltf2, obj, ..."""
    dll = _load()
    dst.parent.mkdir(parents=True, exist_ok=True)
    scene = dll.aiImportFile(str(src).encode("utf-8"), FLAGS)
    if not scene:
        err = dll.aiGetErrorString()
        raise AssimpError(f"import failed: {src}: {err}")
    try:
        # aiReturn_SUCCESS == 0
        rc = dll.aiExportScene(scene, format_id.encode("ascii"), str(dst).encode("utf-8"), 0)
        if rc != 0:
            err = dll.aiGetErrorString()
            raise AssimpError(f"export failed rc={rc}: {dst}: {err}")
    finally:
        dll.aiReleaseImport(scene)


if __name__ == "__main__":
    import sys
    convert(Path(sys.argv[1]), Path(sys.argv[2]), sys.argv[3] if len(sys.argv) > 3 else "glb2")
    print("ok", sys.argv[2])
