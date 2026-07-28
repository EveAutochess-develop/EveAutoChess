# Provenance Rules

This repository is intended to become MIT/BSD-compatible.

Allowed in repo:

- Original Python code.
- Original tests and harnesses.
- Small factual constants required to parse `.gr2` files.
- Documentation written from our own observations.

Not allowed in repo:

- RAD SDK source files.
- RAD DLLs, EXEs, LIBs, PDBs, CHM docs, or Ghidra databases.
- Decompiled code copied from Ghidra.
- Generated code whose source is proprietary binary analysis output.

Allowed locally, outside repo:

- SDK files and DLLs as oracle references.
- Ghidra/PyGhidra projects for behavior study.
- ASAN/GDB/radare2 debugging logs.
- Section hash fixtures generated from private oracle, if they contain only
  hashes, sizes, and filenames.

Implementation rule:

- Use private references to understand behavior.
- Reimplement behavior in our own code.
- Keep notes at algorithm/format level, not copied source level.

