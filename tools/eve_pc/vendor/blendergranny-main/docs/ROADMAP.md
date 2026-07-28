# Roadmap

## Phase 0: Foundation

Status: started.

- Clean addon package exists.
- Header and section table parser works.
- Section scanner covers local sample files.
- Uncompressed section extraction works.
- Private research backend can validate Oodle1 sections from local `.so`.
- Blender importer builds meshes with UVs and vertex groups from bone bindings.
- Skeleton parser reads bone names, parent indices, transforms, and inverse world matrices.
- Blender importer creates armatures and links matching weighted meshes by Armature modifier.
- Material parser reads root materials, diffuse texture file metadata, and mesh material groups.
- Blender importer creates material slots and assigns polygons by topology group.
- Texture resolver searches beside the GR2 file, parent folders, and user-provided roots.
- Blender importer loads resolved texture files into image nodes.
- Blender importer now uses clean native section decompression directly; no
  research DLL/backend required for normal import.
- Oodle1, BitKnit2, and generated classic BitKnit corpora decode/import through
  the public clean path.

Checkpoint:

```bash
python3 tests/test_gr2_parser.py
python3 tools/scan_gr2.py path/to/gr2_samples --decompress
```

## Phase 1: Native Oodle1 Import

Goal: import common SDK/tutorial files without DLL/Wine.

- Implement clean Oodle1 decompressor.
- Decode main section, pointer fixups, and mixed marshalling.
- Walk type tree into Python objects.
- Extract `file_info`.
- Build Blender meshes.
- Import mesh bone bindings and vertex weights as Blender vertex groups.
- Build Blender armatures.
- Refine bone roll/orientation and bind pose conversion.
- Attach basic materials.
- Add embedded texture extraction when Granny image payload decoding is implemented.

Done when:

- `Gryphon.gr2`, `baton.gr2`, `cape.gr2`, `pixo_run.gr2`, and cube samples
  import visibly in Blender.

## Phase 2: Oodle0

Goal: handle older Oodle0 files.

- Use `GrannyRocks.gr2` as primary test target.
- Compare section hashes against local DLL oracle.
- Debug native arithmetic model state with ASAN/GDB.
- Port behavior into clean implementation only after understood.
- Keep crash-prone private Oodle0 backend isolated in subprocesses.
- Keep oracle hashes in `docs/OODLE0_RESEARCH.md`.
- Current clean decoder matches known `GrannyRocks.gr2` section hashes; next
  work is corpus discovery and edge coverage.

Done when:

- All compressed sections in `GrannyRocks.gr2` decompress to oracle hashes.

## Phase 3: BitKnit / BitKnit2

Goal: handle modern 2.11 preferred compression.

- Generated classic BitKnit corpus exists in a local private fixture folder.
- Private corpus census found 4,386 BitKnit2 sections and no classic BitKnit
  sections.
- Primary BitKnit2 oracle target is a local private `.gr2` fixture.
- Clean BitKnit/BitKnit2 section decompression works on generated/import audit:
  112 files, 896 sections, 0 decode/import failures.
- Remaining work: broader generated stress corpus and public fixture curation.

Done when:

- BitKnit and BitKnit2 samples parse and import without DLL.

## Phase 4: Animation

Goal: useful character import.

- Read track groups.
- Extract animation metadata: animation names, duration, timestep,
  oversampling, track groups, vector/transform track names, and first curve
  codec/knot metadata.
- Create Blender action shells with frame range and GR2 metadata.
- Decode constant/identity curves and quantized knot/control curves:
  `D3K16uC16u`, `D3I1K16uC16u`, `D4nK8uC7u`, `D4nK16uC15u`.
- Decode legacy float `granny_curve` animation tracks used by Metin files.
- Evaluate degree-2 curves into sampled frame values.
- Add static keys and sampled transform keys to actions.
- Bind actions to armature.
- Support separate body `.gr2` plus animation `.gr2` selection in importer UX.

Done when:

- SDK walk/run/dance clips and Metin body+animation pairs import as Blender actions.

## Phase 5: Export

Goal: `.gr2` export path.

- Export uncompressed first.
- Write section layout, fixups, mixed marshalling, and type tree.
- Add Oodle1 compression.
- Add BitKnit2 compression last.

Done when:

- Exported file reopens in our importer and local viewer oracle.
