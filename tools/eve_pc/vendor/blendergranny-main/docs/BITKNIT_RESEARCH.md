# BitKnit / BitKnit2 Research

Clean implementation status: container/header inspection, bit/word/chunk streams,
DLL-matched adaptive model tables, state-7 word-window entropy/LZ core, and
native BitKnit2 state-7 stream decode. Verified tags include `0x1`, `0x2`,
`0x3`, `0x12`, `0x14`, `0x50`, `0x14e`, `0x518`, and `0x7d18`; importer now
tries the guarded state-7 stream for any BitKnit2 marker section.
Compressed pointer-fixup and mixed-marshalling metadata blobs are also decoded
through the same BitKnit2 path.

## Local Sample Census

Private corpus:

- Root: local private game asset folder
- Files scanned: 18,386 `.gr2` / `.GR2`
- Parse failures: 0
- Section totals:
  - `oodle1`: 119,205
  - `none`: 23,497
  - `bitknit2`: 4,386
  - `bitknit`: 0 observed

Primary BitKnit2 target:

- Local private `.gr2` fixture
- Version: 7
- Pointer size: 32-bit
- Sections: 8
- Formats: sections 0,1,2,3,4,6,7 use `bitknit2`; section 5 is empty
  `none`.

## Current Clean Findings

- Non-empty BitKnit2 sections start with a 48-byte area before payload bytes.
- First little-endian word uses low 16 bits `0x75b1` on 2,526 sampled
  non-empty BitKnit2 sections.
- Empty BitKnit2 sections have no payload and decode to empty bytes.
- `first_16bit` and `first_8bit` often equal `expanded_size`; section 3 in
  the primary target has both stops at 0, so block splitting differs from
  Oodle0 assumptions.
- The exported BitKnit decompressor processes compressed input in 16-byte
  chunks after the marker/header stage.
- Range-state initialization observed from local 2.11.8 oracle code:
  first payload byte seeds `code = byte >> 1`, `span = 0x80`, and
  `carry_bit = byte & 1`.
- Range-state normalization repeats while `span <= 0x800000`: fold next byte as
  `code = (((code * 2) + carry_bit) << 7) | (byte >> 1)`, then `span <<= 8`
  and `carry_bit = byte & 1`.
- DLL range helpers are now mapped and ported:
  - `0x1006c120`: `peek(total)`, saving `scale = span / total`;
  - `0x1006c150`: `peek_shifted(shift, cap)`, saving `scale = span >> shift`;
  - `0x1006c180`: shifted/capped take;
  - `0x1006c210`: uniform take;
  - `0x1006c3c0`: consume a previously scaled low/width range.
- The public export is a thin wrapper around the internal BitKnit core; the
  wrapper returns success in `AL`, so probe helpers mask the raw integer to one
  byte before reporting `ok`.
- It maintains four decode contexts selected by output position modulo 4.
- Two model families are visible from behavior/binary structure:
  - literal/delta-symbol model stride: `0xd74` bytes per modulo context
  - match/length/offset model stride: `0x1d4` bytes per modulo context
- Symbol range observations:
  - `< 0x100`: literal/delta byte path
  - `0x100..0x11f`: match/offset path without extra high bits
  - `>= 0x120`: match/offset path with extra bits
- Adaptive model update adds `31` to symbol weight and decrements a countdown;
  reset/rebuild happens when the countdown reaches zero.
- The DLL model object layout at `0x10073000..0x10073493` is now partially
  identified:
  - `+0x00`: total weight (`u16`);
  - `+0x02`: total plus growth/escape allowance (`u16`);
  - `+0x04`: reset/rebuild threshold (`u16`, clamped between `0x80` and roughly
    half of `+0x08`);
  - `+0x06`: adaptive growth step (`u16`, doubles until threshold);
  - `+0x08`: high threshold (`u16`, min `0x100`, max `0x3b38`);
  - `+0x0a`: active symbol count (`u16`);
  - `+0x0c`: cached symbol count for cumulative ranges (`u16`);
  - `+0x0e`: symbol capacity (`u16`);
  - `+0x10`, `+0x14`, `+0x1c`: parallel `u16` arrays for symbol order,
    weights, and reverse lookup/cumulative mapping;
  - `+0x50`: cumulative probability table built against `0x20000` scale and
    anchored around `0x8000..0xc000`.
- `0x10073130` and `0x100732e0` are two rebuild/rescale variants. Both halve
  weights, drop zero-weight entries, maintain reverse maps, then move the
  heaviest symbol toward the active tail. `0x10073400` rebuilds the cumulative
  probability table.
- Clean code now has `BitKnitAdaptiveModel`, `BitKnitDecoderState`, chunk input
  stream, range-to-model symbol decoding, range decoder primitives, symbol
  classification, explicit decoded token records, and `BitKnitOutputWindow`
  scaffolds for the four modulo contexts. Initial distributions still need
  oracle matching.
- With uniform clean model assumptions, primary section 0 first decoded literal
  bucket is symbol `121`, leaving range state `code=0x000b5dd3`,
  `span=0x003f618c`. This is a probe checkpoint, not proof that Granny's
  initial literal distribution is uniform.
- Literal symbols are treated as modulo-4 deltas: the emitted byte is
  `(output[offset - 4] + symbol) & 0xff`, with zero base for the first four
  output bytes. This matches the observed four-context design and keeps the
  LZ/output side ready while entropy decoding is still under research.
- Main decoder loop around `0x10069d10..0x1006a33e` confirms the same delta
  model at DLL level:
  - context is `output_pos & 3`;
  - per-context literal model base is `stack+0x1c4 + context*0xd74`;
  - `0x1006a1c0..0x1006a1f4` emits literal deltas by subtracting the byte four
    positions back, then updates the context model through `0x1006b2e0`;
  - if `(state+0x0c) ^ output_pos >= 0x10000`, it calls `0x1006b110`, likely a
    block/history refresh;
  - non-literal/control path calls `0x1006b040`, so that is the next high-value
    RE target for match/copy and section-control records.
- `0x1006b040` first updates the literal/control model with `symbol + 0xfe`,
  then decodes a distance/control symbol through `0x1006b8f0`, then updates a
  recent-distance table. `0x1006b8f0` has two distance forms:
  - symbols `< 8`: recent-distance slots;
  - symbols `>= 8`: direct slots with `low5 = (symbol - 8) & 31` and
    `extra_group = bsr(((symbol - 8) >> 5) + 1)`;
  - direct symbols with `extra_group != 0` consume extra bits through
    `0x1006bca0`.
- `0x1006bca0` packs extra-bit intervals:
  - `bit_count < 16`: one record `(low=value & ((1<<bits)-1), tag=0x8000|bits)`;
  - `bit_count >= 16`: high record `(value>>16, 0x8000|(bits-16))`, then low
    16-bit record `(value & 0xffff, 0xc000)`.
- `0x1006b880` initializes real model table set for the `0x10069a90` core:
  four literal/control models at stride `0xd74`, four long-distance models at
  stride `0x1d4`, and one short-distance model. Clean helpers now reproduce
  three DLL linear cumulative tables:
  - literal/control: `0x12c` symbols, step `0x7fdc`, divisor `0x108`,
    update weight `0x2d5`;
  - short distance: `0x15` symbols, step `0x8000`, divisor `0x15`,
    update weight `0x3ec`;
  - long distance: `0x28` symbols, step `0x8000`, divisor `0x28`,
    update weight `0x3d9`.
- Native state-7 decode now matches the 2.11.8 oracle for all non-empty
  BitKnit2 sections in the primary sample: sections 0, 1, 2, 3, 4, and 6.
- Metadata fixup arrays can be stored as a 4-byte payload-size prefix followed
  by a BitKnit2 stream. Clean `load_sections()` now decodes those blobs before
  applying pointer/mixed-marshalling records. The primary sample loads 1,052
  pointer fixups, 1 mixed-marshalling fixup, 2 meshes, 11,915 vertices, 22,847
  triangles, and a 90-bone skeleton.
- The 64 KiB boundary is now mapped in the DLL:
  - `0x10068f10` is the state-7 decode core and returns with state `3` when
    output reaches the current block end.
  - `0x10069770` sees state `3` plus both word windows equal `0x10000`, then
    either marks stream done or advances the output end to the next 64 KiB
    block and returns to state `2`.
  - State `2` reads the next block word: zero means raw copy state `4`; nonzero
    means compressed state `7` without consuming that word.
  - Clean multi-block stream support now preserves DLL model/recent-distance
    state across blocks and reseeds range windows at each compressed block.
- Probe result: applying that literal/control table directly at payload byte 48
  on primary section 0 yields symbols `70,97,106,63...`, not oracle zeroes.
  So full decoder entry needs chunk/FSM staging from `0x10069770` /
  `0x100698c0`, not raw range start only.
- `tools/trace_bitknit_control.py` now prints that distance shape. Current
  zero-biased primary section 0 probe sees first match-model symbols
  `17, 17, 51`, mapping to direct distances `(low5=9, group=0)`,
  `(low5=9, group=0)`, and `(low5=11, group=1)`. This is still under candidate
  model assumptions, but the symbol shape now matches DLL control flow.

## Source / Oracle Notes

- Local extracted SDK file list includes `binktc.c`,
  `granny_bink.cpp`, `granny_bink0_compression.cpp`, and
  `granny_bink1_compression.cpp`. These are Bink texture compression files, not
  Granny file-section BitKnit compression.
- The 2.11.8 public header exposes `GrannyBitKnitCompress`,
  `GrannyBitKnitCompressEnd`, and `GrannyBitKnitDecompress`, but the matching
  source file is not present in the extracted source list.
- Local 2.11.8 `granny2.dll` exports `_GrannyBitKnitDecompress@16`; keep it as
  oracle only. Expected DLL SHA-256:
  `786954a7652133f793b1e974d791fed8d2ae24d5ad3accd92310d02ef18beca3`.
- Export route check: `_GrannyBitKnitDecompress@16` at `0x10062bb0` calls
  `0x10016ad0`, which calls `0x1006bd70`; wrapper reports success when that
  internal routine returns `0`.
- `0x1006bd70` is the small top-level decompressor driver: it initializes
  output state with `0x100699f0`, initializes input/chunk state with
  `0x100698c0`, then asks `0x100698c0` to feed bytes through `0x10069770`.
- Clean `probe_bitknit_chunk_fsm_entry` now models the first `0x10069770`
  decisions. The observed BitKnit2 path is: marker `0x75b1`, then nonzero
  block word at offset 2, then state `7` (`0x10068f10` compressed handler)
  without consuming that block word. `tools/scan_bitknit_fsm.py` found first
  1000 non-empty Ymir BitKnit2 sections all start in state `7`.
- `0x10068f10` main decode loop confirms first model grammar:
  - symbols `< 0x100`: literal delta byte;
  - symbols `0x100..0x11f`: match length `symbol - 0xfe`, i.e. `2..33`;
  - symbols `>= 0x120`: extended length, reading `symbol - 0x11f` extra bits,
    then `expanded_symbol = (1 << extra_bits) + 0x11e + extra_value` and
    `length = expanded_symbol - 0xfe`.
  Clean helper `describe_length_symbol` encodes this.
- Direct match distance is a two-model grammar in `0x10069454..0x100695c5`.
  Long-distance symbols `< 8` select the recent-distance ring. Long-distance
  symbols `8..39` enter the direct path, then a short-distance symbol provides
  the extra-bit count. Clean helper `describe_direct_distance_symbols` now
  encodes the derived formula:
  `distance = long_symbol + ((extra_value - 1) << 5) + ((0x20 << short_symbol) - 7)`.
  This gives tier 0 distances `1..32` from long symbols `8..39`, then tiered
  ranges such as `33..96` when short symbol is `1`.
- `0x10068f10` does not use the older byte-oriented range scaffold for this
  hot path. It uses a 15-bit value from a 32-bit window, consumes DLL cumulative
  table ranges, and refills by appending little-endian `u16` words when the
  updated window drops below `0x10000`. Clean `BitKnitWordRangeDecoder` and
  `lookup_dll_table_symbol` now model this exact consume/refill step.
- Output/input state initialization is now located:
  - `0x100699f0` initializes output pointers, state `+0x38 = 1`,
    word windows `+0x3c = 0x10000` and `+0x40 = 0x10000`, eight recent
    distances to `1`, packed recent selector `+0x34 = 0xfac688`, and the DLL
    model tables via `0x1006b880`.
  - When the chunk FSM reaches state `7`, `0x10068f10` calls `0x1006ba30`
    before the main token loop. That routine consumes little-endian `u16` words
    from the current input pointer, seeds two 32-bit word-range windows, and
    advances the input pointer. Porting `0x1006ba30` cleanly is the next bridge
    between `probe_bitknit_chunk_fsm_entry` and `BitKnitWordRangeDecoder`.
- Clean `seed_bitknit_state7_word_ranges` now ports `0x1006ba30`, including
  the low-nibble `+0x10` extra-bit count, conditional `u16` refills, and final
  sentinel bit in the extra window. `tools/trace_bitknit_entropy.py
  --model state7-dll-literal` now enters via the observed chunk FSM offset
  instead of the old payload-offset range scaffold.
- `tools/trace_bitknit_entropy.py --model state7-token` now performs the first
  clean state-7 token pass: shared range/extra word pointer, DLL literal table,
  literal delta writes, length symbol decoding, long-distance symbol decoding,
  short-distance direct tier, and direct-distance formula. On primary section 0
  it emits four literal tokens then a length-7 direct match, but the direct
  distance is impossible for output offset 4. This is a useful failing
  checkpoint: the next missing piece is exact DLL adaptive table update/context
  state (or table selection), not the match copy formula.
- Correction: the literal cumulative table was not the simple 300-symbol linear
  range previously guessed. `0x1006b3d0` writes a 264-entry head up to `32608`,
  then a dense tail `32732..32768`, so total is exactly `0x8000`. Clean
  `make_dll_literal_table_profile` now matches that initialization.
- Correction: state 7 has a one-byte pre-loop literal at
  `0x100690ac..0x10069104` when output is still at the block start. It writes
  the low byte of the first seeded range window, then swaps the active model
  window roles. On primary section 0 this byte is `0`, matching the oracle.
- Correction: the main loop alternates two 32-bit model windows. Every model
  decode consumes the active window, then swaps active/other. With this fixed,
  primary section 0 now traces: initial zero byte, length-11 recent-distance-1
  copy to offset 12, literal `3` at offset 12, length-7 distance-8 copy to
  offset 20, then length-7 recent-distance-1 copy to offset 27. This matches
  the oracle's early sparse-u32 shape much more closely.
- Clean `BitKnitRecentDistanceState` now models the recent-distance selector
  path for recent symbols. Direct-distance recency insertion still needs the
  `0x100695c7..0x100695e4` swap path before full copy loop promotion is exact.
- Direct-distance insertion is now modeled: source slot is
  `(selector >> 18) & 7`, target slot is `(selector >> 21) & 7`; the previous
  source-slot distance moves to target, and the new direct distance is written
  into source. On the primary section this records distance `8` in slot `6`,
  letting later recent symbol `6` resolve to `8`.
- Correction: state-7 literal deltas use the last match distance as their base,
  not the earlier modulo-4 base helper. The DLL literal path reads
  `output[offset - last_distance] + symbol`. This explains primary section 0's
  oracle prefix exactly: after a direct distance-8 match, literal symbol `3` at
  offset `20` becomes `6` (`output[12] + 3`), and literal symbol `251` at
  offset `28` becomes `1` (`output[20] + 251`, modulo 256).
- Correction: direct-path short-distance symbol decode consumes the active
  short-distance window without swapping the two model windows. The long
  distance decode swaps, then the short distance decode updates that active
  short window in place while extra bits are read from the other window. This
  fixes the next-token state after distance-8 matches.
- State-7 prefix logic is now reusable in clean core as
  `decode_bitknit_state7_prefix`. It shares the same mechanics previously
  prototyped in `tools/trace_bitknit_entropy.py --model state7-token` and can
  produce a bounded native prefix without going through the DLL.
- On cached 2.11.8 oracle output for primary section 0, the reusable native
  state-7 prefix matches the first 96 bytes exactly. At 128 requested bytes,
  the first mismatch is offset `96`: clean currently emits
  `00 03 e4 5c 65...`, while oracle has `14 00 00 00...`. This is now the next
  decoder target. Since the first 96 bytes include multiple literals, direct
  matches, recent matches, extra-length match, and match-copy behavior, the
  remaining divergence is probably exact model mutation/rebuild state or one
  missing control branch after the first large recent-distance run.
- Correction: extended-length extra bits are read from the active/opposite
  window used by `esp+14`, then the windows swap again; direct-distance extra
  bits still use the non-swapped `esp+10` path. Clean
  `read_swapped_extra_bits` now models the extended-length path separately
  from direct-distance extras.
- With the extended-length window fix, primary section 0 now matches cached
  DLL oracle through at least 8192 bytes. A quick probe with a 12000-byte target
  stops at output offset `8384` because the next direct distance exceeds
  current output. That makes offset `8384` the next concrete BitKnit2 state-7
  target; likely remaining issue is exact adaptive model rebuild after enough
  symbols, or another long/short-distance state nuance.
- Clean `BitKnitDllAdaptiveModel` now implements the DLL's delayed model
  mutation: per-symbol weight increments by `0x1f`, countdown decrements, and
  when it reaches zero the symbol receives the model-specific larger increment
  before cumulative entries are rebuilt halfway toward running weight sums and
  weights reset to 1.
- With delayed model rebuilds enabled, primary section 0 (`header_tag=0x50`)
  now decodes fully and matches the cached/direct 2.11.8 oracle SHA-256:
  `ba9d4da6c28d8e482b9f5e13f1e7172677d4341df0f8ca45262207d71750f7fb`.
  `decompress_bitknit` now enables this native state-7 path only for proven
  BitKnit2 section 0 / tag `0x50`; other sections remain unsupported until
  individually proven.
- `tools/oracle_sections.py` now checks the helper sibling `granny2.dll`
  against that hash by default.
- Local 2.9.12 `preprocessor.exe` runs under Wine, but `ListCommands` shows
  only Oodle1 `Compress`, not `CompressBitKnit`/`CompressBitKnit2`. BitKnit1
  fixture generation needs either a 2.11 preprocessor binary or a small private
  DLL caller outside this repo.
- `tools/probe_bitknit_dll.py` calls the 2.11.8
  `_GrannyBitKnitDecompress@16` export directly on raw section bytes. Use those
  hashes for clean decompressor tests.
- `tools/trace_bitknit_entropy.py` traces the current clean range/model
  scaffold for literal or match symbols. Use it to compare candidate initial
  model tables and range transitions; it is not a full stream decoder yet.
- `tools/compare_bitknit_prefix.py` runs the 2.11.8 direct decompressor oracle
  and compares current clean prefix attempts against oracle bytes. On primary
  section 0, uniform literal-only decoding emits `79 5c` then hits non-literal
  symbol `370`, while oracle starts `00 00 00 00 ...`. This proves the next
  blocker is model/branch initialization, not the output-window byte math.
- `tools/search_bitknit_zero_bias.py` brute-forces simple zero-heavy literal
  profiles. On primary section 0, weights around `3985` make the clean
  literal-only path match the first 12 oracle bytes (`00` repeated), then stop
  on a non-literal/control symbol around `516` exactly where the oracle has
  byte `03`. This suggests the true initial literal table is strongly
  zero-biased and the next event is likely match/control grammar, not plain
  literal `3`.
- `BitKnitDecodedToken` now records decoded symbol kind. With zero weight
  `3985`, the comparator reports 12 literal zero tokens followed by
  `kind="match"`, `symbol=516`, `needs_extra_bits=true` at output offset 12.
- `tools/trace_bitknit_control.py` continues from that first match/control
  token into the separate match model, so length/distance grammar can be probed
  without resetting range state.
- `tools/summarize_bitknit_profiles.py` compares zero-bias probes across all
  BitKnit2 sections. Results show the simple zero-heavy literal profile is not
  universal: section 0 matches 8-12 leading zero bytes, while sections 1, 2, 3,
  4, and 6 need different grammar/table assumptions almost immediately. The
  literal model is likely header/context dependent, and some sections start
  with match/control tokens.
- `tools/scan_bitknit_corpus.py` scans many Ymir `.gr2` files, caches small
  2.11.8 direct-decompressor oracle blobs under `research_artifacts/`, and
  groups rows by header tag / first oracle word. Use it before changing decoder
  assumptions so we do not overfit one section.
- Early targeted corpus scan over three BitKnit2 files found ten non-empty
  sections with distinct header tags. Section 0 rows commonly start with
  zeroed oracle words, while section 6 rows commonly start with `02 00 00 00`.
  Header tags vary even when first oracle words repeat, so the next decoder
  step should model section role / control grammar, not a single global
  zero-biased literal table.
- `tools/scan_bitknit_controls.py` now scans candidate literal zero weights and
  records the first non-literal control token with its low 5 bits and high
  group. This keeps the research honest when a symbol appears at output offset
  zero: those events cannot be normal LZ copies, so the clean model names them
  as `control` while preserving the older `match` field for compatibility.
- Control scan checkpoint over the primary file plus two `treasure_hunt_goblin`
  files:
  - primary section 0 can match twelve leading zero bytes with zero weight
    around `3985`;
  - another section 0 (`front_damage`) matches five leading zero bytes before
    control `symbol=342`, `group=1`, `low5=22`;
  - `front_dead` section 0 only matches one leading zero before control
    `symbol=489`, `group=6`, `low5=9`;
  - section 6 rows start with oracle `02 00 00 00...`, but current literal-only
    probes cannot produce that prefix. This makes section 6 the best next target
    for true control grammar.
- `tools/probe_bitknit_prefix_mutations.py` flips compressed input bits and
  reports direct-decompressor output prefixes in one Wine process. On primary
  section 6, flipping bytes `48..63` either fails the decoder or leaves the
  first 16 output bytes unchanged; successful flips first affect output at
  offsets around `1185..1377`. This strongly suggests section 6's first records
  are produced by header/control initialization, not ordinary payload literals.
- The same prefix-mutation helper now supports `--filter prefix-changed` and
  `--filter later-changed` / `--filter fill-bits` so future mutation probes stay
  compact. On primary section 6, header bytes `4..9` are the only tested bytes
  that can alter the first 16 output bytes. Flipping byte 5 bits `0..5` produces
  valid outputs with repeated prefixes like `06 04 04...`, `0a 08 08...`,
  `12 10 10...`, up to `82 80 80...`. This makes header word 1 (`0xfb6fc0a2`
  on the primary sample) a strong candidate for early fill/delta control state.
- `--filter fill-bits` shows the same signed 8-bit fill field across three
  section 6 samples, but the bit offset shifts by file:
  - primary `290325alin_frz_vafreacamarc`: bit positions `38..45`;
  - `front_damage`: bit positions `48..55`;
  - `front_dead`: bit positions `52..59`.
  Flipping those bits yields `fill` values `1`, `-2`, `4`, `8`, `16`, `32`,
  `64`, `-128`; oracle prefix becomes `(fill + 2) & 0xff` followed by repeated
  `fill`. Baseline has `fill=0`, hence prefix `02 00 00...`. This strongly
  indicates BitKnit2 section 6 reads a bit-packed signed byte from header word
  stream and uses it as first record fill/delta.
- Clean code now has `BitKnitHeaderBitReader`, header bit peek helpers, and
  section 6 fill-record helpers. For the three known section 6 samples, the
  discovered bit offsets read seed byte `2`; clean helper maps that to
  `fill = sign_extend((seed - 2) & 0xff, 8)` and predicts the observed
  `02 00 00...` prefix. This is a research checkpoint, not full section 6
  decode yet, because the rule selecting bit offset `38/48/52` is still unknown.
- `tools/find_bitknit_section6_fill.py` scans header bits for seed bytes that
  predict the first section 6 fill record. On the three current samples there
  are four baseline candidates per file, and the mutation-proven offsets are in
  those sets:
  - primary candidates include `38`;
  - `front_damage` candidates include `48`;
  - `front_dead` candidates include `52`.
  The first match after the 32-bit marker/tag word selects the mutation-proven
  offset in all three known samples (`38`, `48`, `52`). Clean helper
  `find_section6_control_fill_candidate` now encodes that checkpoint. This is
  still a local rule until more section 6 files are tested. A targeted scan of
  six files (primary plus `treasure_hunt_goblin`) selected offsets
  `38`, `48`, `52`, `36`, `64`, and `48`, all predicting the observed
  `02 00 00...` first record.
- `decode_section6_fill_record_from_header` now emits that first 32-byte record
  from the selected header seed. `tools/compare_bitknit_prefix.py
  --section6-fill-prelude --bytes 32` matches oracle exactly on the six-file
  section 6 set above. This is the first clean native BitKnit2 section 6 output
  slice, but it only covers the initial fill record.
- The same prelude currently repeats the selected fill record for the first two
  32-byte records. `--section6-fill-prelude --bytes 64` matches the same
  six-file section 6 set exactly. At 96 bytes the clean slice now reports a
  length mismatch at offset 64, making record 2 the next real grammar target
  (zero record on the primary sample, value `8` on the `treasure_hunt_goblin`
  samples).
- `tools/probe_bitknit_prefix_mutations.py --filter record-changed` now reports
  compact per-record u32 changes. On `front_damage.gr2` section 6, record 2
  (offset 64) is sensitive to header bytes `16..17`: flipping byte 17 bits
  changes the record tag from baseline `8` to `6`, `4`, `17`, `25`, `41`,
  `74`, and `140`; flipping byte 16 bits 5/7 changes it to `9`. Early payload
  bytes `48..96` do not affect the first 96 output bytes. So record 2 is still
  header/control prelude, not payload entropy.
- `tools/analyze_bitknit_section6_prelude.py` now summarizes section 6 header
  prelude rows from cached oracle data. A 12-file scan found the primary sample
  starts `[2, 2, 0, 8]`, while eleven animation-ish samples start
  `[2, 2, 8, 4]`. This confirms records 2 and 3 are structured header prelude
  tags, but also warns against hardcoding one global pattern.
- Header bits in bytes `24..63` that still decompress successfully keep the
  first 16 bytes unchanged and first affect later records: e.g. offsets `24`,
  `25`, `34`, `43`, `56`, `57`, and `61` first differ at output offsets
  `160..1377`. Those output offsets align with the 32-byte record grid, so
  header/payload regions likely seed separate record ranges.
- `tools/analyze_bitknit_oracle_layout.py` summarizes oracle output as sparse
  u32 records. Primary section 6's first 512 bytes contain only u32 values at
  offset `0 mod 32`: `2`, `8`, and `19`. Two `treasure_hunt_goblin` section 6
  samples show the same 32-byte record layout, with values `2`, `4`, `5`, `8`,
  and `19`. This makes section 6 look like a 32-byte-stride type/member table,
  and the BitKnit control grammar likely emits repeated zero-filled records
  with small u32 tags.
- `tools/probe_bitknit_mutations.py` flips header/payload bytes in one Wine
  process and reports output diff counts. Its generated executable and input
  copies stay under ignored `research_artifacts/`.
- `tools/oracle_sections.py` loads the whole file through Granny; sections 0 and
  6 in the primary target differ from direct BitKnit output, likely because file
  loading applies fixups or post-load section transforms. Use it for import
  oracle checks, not raw decompressor hashes.

## Oracle Hashes

Direct decompressor hashes from `tools/probe_bitknit_dll.py`:

```bash
python3 tools/probe_bitknit_dll.py 'path/to/bitknit2_fixture.gr2' --section 0
```

| Section | Size | SHA-256 |
| --- | ---: | --- |
| 0 | 28864 | `ba9d4da6c28d8e482b9f5e13f1e7172677d4341df0f8ca45262207d71750f7fb` |
| 1 | 373792 | `97e8ddd89cf9c1a304e1f5d73e70f6d07a026760785b6fc970aa5ef6f16eae22` |
| 2 | 270888 | `778810305aa259453bcd99d3a87abd40291d6072dbe2525ceb46e9bd93f06b0f` |
| 3 | 9376 | `ef03f49816290ffdb32d737b1da7a4d4508ceeba6a6bf8882af5114bf24be5ec` |
| 4 | 3276 | `3ab52a1bee394801b45e5f11f3d42ad9d70209b647da6143cabb3ac4f72ce14d` |
| 6 | 13632 | `9804f0d40ee5da4cf97a754479930545638c474f846591b22f2fa67ffb9280dd` |

Red/green check:

```bash
python3 tools/check_bitknit_hashes.py 'path/to/bitknit2_fixture.gr2'
```

Current expected result: unsupported for non-empty compressed sections until the
clean decoder exists.
