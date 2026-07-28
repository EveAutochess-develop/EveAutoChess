# Oodle0 Research Notes

Status: clean decoder implemented for known Oodle0 fixture. Do not ship SDK
source, RAD binaries, Wine helpers, decompiled code, or dumped sections in this
repository.

## Current Target

- File: local private `GrannyRocks.gr2` fixture
- GR2: version 6, 32-bit pointers, not byte-reversed
- Sections: 5 Oodle0 sections + 1 uncompressed section

## Historical Unsafe Probe Result

Command:

```bash
python3 tools/probe_oodle0.py "path/to/GrannyRocks.gr2" --timeout 3
```

Result:

| Section | Compression | Current private native result |
| --- | --- | --- |
| 0 | oodle0 | crash, SIGSEGV |
| 1 | oodle0 | crash, SIGSEGV |
| 2 | oodle0 | crash, SIGSEGV |
| 3 | oodle0 | crash, SIGFPE |
| 4 | oodle0 | crash, SIGSEGV |

GDB section 0:

```text
SIGSEGV in Arith_decompress
called from gr2_oodle0_decompress
```

This confirmed the old private native Oodle0 path had to stay isolated during
research. Normal importer now uses the clean Python decoder, not this backend.

## Oracle Hashes

Command:

```bash
python3 tools/oracle_sections.py "path/to/GrannyRocks.gr2" --timeout 30
```

Uses local `gr2_raw_dump.exe` + Granny 2.11.8.0 `granny2.dll` outside this repo.
`tools/oracle_sections.py` checks the helper sibling DLL SHA-256 by default:
`786954a7652133f793b1e974d791fed8d2ae24d5ad3accd92310d02ef18beca3`.
On Linux it runs through Wine; on Windows it runs directly. This is an oracle only, not a
shipping path.

| Section | Size | SHA-256 |
| --- | ---: | --- |
| 0 | 1373600 | `5927c92a3c26f043e3d4666006c68c10cf00ab241c6243888ca8866a6970c8b2` |
| 1 | 136864 | `e555866abd0b7cf5b8592e61e5e9d00aaf6ba186172c78ff989dd8abf6677fa9` |
| 2 | 57084 | `eb91551a31cbe807155d0c1b7023c896a3a091c9ca0c5372379282aa3e955ea7` |
| 3 | 183104 | `9bcbb9dd5df90dee1cbfe7dcdbe5bd614193940157befe32c4a0dfb8c5ee6d77` |
| 4 | 76128 | `6be27601874b3ca35aeb7ec5cdc1076c4b294001c9c98a92d118b4de4a336f67` |
| 5 | 855172 | `64d543889e49883f74f20bb5ccd6e5a3d429784758d9abeb8d574d3a21adc5c3` |

Section 5 is uncompressed; its oracle hash matches the clean backend.

## Clean-Room Path

1. Keep `tools/oracle_sections.py` as external oracle hash generator.
2. Keep `tools/probe_oodle0.py` as crash-safe private backend runner.
3. Use `tools/inspect_oodle0.py` and `parse_oodle0_plan()` to inspect the clean
   36-byte Oodle0 section container.
4. Implement Oodle0 in clean Python or clean native code from behavior notes,
   not by copying SDK code into this repo.
5. Validate each section against the oracle hashes above.
6. Only then wire Oodle0 fully into `decompress_section`.

## Clean Reader Milestone

Implemented:

- `io_scene_gr2.gr2.decompress.oodle0.parse_oodle0_plan`
- `io_scene_gr2.gr2.decompress.oodle0.decompress_oodle0`
- `tools/inspect_oodle0.py`
- `tools/check_oodle0_hashes.py`
- clean backend path that decodes all five `GrannyRocks.gr2` Oodle0
  sections to known oracle hashes

For `GrannyRocks.gr2`, all Oodle0 sections use:

- Header size: 36 bytes
- Block count: 3
- `max_byte_value`: 256
- `max_offset`: 262136

Current coverage:

- `tools/check_oodle0_hashes.py` passes for all 5 compressed sections.
- `tools/scan_gr2.py ... --decompress` passes for all 6 sections.
- `load_sections()` completes on `GrannyRocks.gr2` and reads 34,820 pointer
  fixups plus 9 mixed marshalling fixups.
- Parser-only private corpus census found 27,755 readable `.gr2` files and only
  20 Oodle0 sections. All 4 Oodle0 file hits are duplicate `GrannyRocks.gr2`
  copies, and all 4 copies decode 5/5 Oodle0 sections cleanly.

Remaining risk:

- Only one known Oodle0 source file currently validates the decoder.
- Need more 2.6/2.7/2.8-era samples, especially files with different block
  split points, byte ranges, and offset models.

## Cross-Platform Rules

- Research library path can be set with `GR2_RESEARCH_LIB`.
- Oracle helper path can be set with `GR2_ORACLE_HELPER`.
- Windows should run helper directly.
- Linux can run helper through Wine for oracle generation only.
- Final addon must not depend on Wine, RAD DLLs, SDK libs, or helper EXEs.
