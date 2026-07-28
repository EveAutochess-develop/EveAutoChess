# Release Checklist

## Public Repository

- MIT `LICENSE` present.
- No proprietary SDK files, Granny/RAD/Oodle binaries, game assets, generated
  private corpora, Ghidra projects, or decompiled source.
- `research_artifacts/`, binaries, caches, and build outputs ignored.
- README uses generic paths only.
- Tests skip optional private fixtures when environment variables are unset.

## Addon Package

- Package one unified addon for Linux and Windows.
- Include runtime `io_scene_gr2/`, `README.md`, and `LICENSE`.
- Exclude `research_artifacts/`, `tools/*dll*`, private oracle helpers, caches,
  local sample files, and `research_native.py` from release zips.

## Verification

- `python3 tests/test_gr2_parser.py`
- `python3 -m compileall -q io_scene_gr2 tools tests`
- Blender headless smoke import on Linux.
- Blender UI import on Linux.
- Blender UI import on Windows with same zip.

## First Public Scope

- Importer first.
- Exporter marked planned/WIP until round-trip tests exist.
- Known limitations documented: Oodle0 broader coverage, visual animation QA,
  scale/orientation edge cases, texture formats not decoded from embedded image
  payloads.
