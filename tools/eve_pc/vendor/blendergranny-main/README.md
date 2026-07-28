# Blender Granny2 Native Addon

<p align="center">
  <a href="https://buymeacoffee.com/CiupiX">
    <img src="https://img.shields.io/badge/%E2%98%95-Buy%20Me%20a%20Coffee-ff813f?style=for-the-badge&logo=buymeacoffee&logoColor=white" alt="Buy Me a Coffee">
  </a>
</p>

Clean-room Blender addon for importing Granny2 `.gr2` files. Export support is
in progress.

## Status

This project is in active development. Current importer support:

- Native section parser and fixup loader.
- Native decompression for raw, Oodle1, known Oodle0 fixtures, BitKnit, and
  BitKnit2.
- Meshes, UVs, material slots, texture path resolution, vertex groups, and
  armatures.
- Animation actions from embedded clips or a separate animation `.gr2` file.
- Linux-tested. Windows should use the same addon package, but still needs a
  real Blender smoke test.

## Install

1. Download `io_scene_gr2-*.zip` from a release, or build it:

   ```bash
   python3 tools/package_addon.py
   ```

2. In Blender, open `Edit > Preferences > Add-ons > Install...`.
3. Select the addon zip.
4. Enable `Import-Export: Granny2 Native (.gr2)`.
5. Use `File > Import > Granny2 (.gr2)`.

For character animation, select the body `.gr2` as the main file and set
`Animation GR2` to a separate animation file.

## Compatibility

One addon package should support Linux and Windows. The runtime importer is
Python-only and does not require Wine, Granny DLLs, SDK libraries, or native
shared libraries.

| Feature | Status |
| --- | --- |
| Raw sections | Working |
| Oodle1 | Working on tested corpus |
| Oodle0 | Working on known fixture; broader corpus still needed |
| BitKnit | Working on generated corpus |
| BitKnit2 | Working on tested corpus |
| Mesh import | Working |
| Skeleton import | Working |
| Animation import | Working, needs broader visual QA |
| Export | WIP: raw mesh + skeleton + weight `.gr2` writer works on local character round-trip |

Current exporter writes uncompressed mesh geometry, UVs, material slots, triangle
material groups, texture paths/sizes, skeleton names/parents, imported Granny
bind transforms, bone bindings, vertex weights, and 16-bit/32-bit triangle
indices. Animations and BitKnit2 export are next milestones.

Exported raw files include Granny-compatible file CRCs computed over the section
table and following payload bytes.

Exporter also writes a root `Models` array with model mesh bindings so Granny
Viewer can attach exported meshes to a scene model.

Exporter writes `ArtToolInfo` axis metadata with `UpVector=(0, 0, 1)`, matching
Blender/Metin Z-up character data so Granny Viewer can open files upright by
default.

## Development

Run parser tests:

```bash
python3 tests/test_gr2_parser.py
```

Run Blender smoke import:

```bash
blender --background --python tools/blender_smoke_import.py -- --no-textures path/to/file.gr2
```

Run exporter collection smoke test:

```bash
blender --background --factory-startup --python tools/blender_export_collect_smoke.py
```

Private sample roots are optional. Tests skip unavailable files. To enable local
fixture checks:

```bash
GR2_SAMPLE_ROOT=/path/to/granny_samples \
GR2_YMIR_SAMPLE_ROOT=/path/to/ymir_samples \
python3 tests/test_gr2_parser.py
```

## Legal

License: MIT.

Do not commit proprietary SDK files, Granny/RAD/Oodle binaries, game client
assets, generated corpora from private assets, Ghidra databases, or decompiled
source. Research helpers may compare against local private oracles, but the
runtime addon must stay clean and redistributable.

## ☕ Support

<p align="center">
  <sub>fuel the reverse-engineering</sub><br><br>
  <a href="https://buymeacoffee.com/CiupiX">
    <img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" width="180" alt="Buy Me a Coffee">
  </a>
</p>
