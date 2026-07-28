import hashlib
import os
from pathlib import Path
import sys
import tempfile
import zlib

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from io_scene_gr2.gr2.constants import (
    COMPRESSION_BITKNIT2,
    COMPRESSION_NONE,
    COMPRESSION_OODLE0,
    COMPRESSION_OODLE1,
)
from io_scene_gr2.gr2.decompress import decompress_section
from io_scene_gr2.gr2.decompress.bitknit import (
    BITKNIT2_MARKER,
    BITKNIT_CHUNK_SIZE,
    BITKNIT_EXTRA_MATCH_BASE,
    BITKNIT_LITERAL_SYMBOLS,
    BITKNIT_MATCH_SYMBOLS,
    BITKNIT_MODEL_UPDATE,
    BITKNIT_RANGE_NORMALIZE_LIMIT,
    BITKNIT_RANGE_INITIAL,
    BITKNIT_RECENT_DISTANCE_COUNT,
    BITKNIT_SECTION6_RECORD_SIZE,
    BITKNIT_SECTION6_INITIAL_FILL_RECORDS,
    BITKNIT_INITIAL_RECENT_SELECTOR,
    BitKnitOutputWindow,
    BitKnitAdaptiveModel,
    BitKnitDllAdaptiveModel,
    BitKnitHeaderBitReader,
    BitKnitModelProfile,
    BitKnitRecentDistanceState,
    BitKnitRangeDecoder,
    BitKnitSymbolRange,
    BitKnitState7WindowDecoder,
    BitKnitWordRangeDecoder,
    classify_bitknit_symbol,
    decode_bitknit_state7_prefix,
    describe_direct_distance_symbols,
    describe_distance_symbol,
    describe_length_symbol,
    describe_control_symbol,
    describe_match_symbol,
    decode_section6_fill_record_from_header,
    decode_section6_initial_fill_records_from_header,
    find_section6_fill_candidates,
    find_section6_control_fill_candidate,
    make_header_bit_reader,
    make_state7_decoder_after_initial_literal,
    lookup_dll_table_symbol,
    make_section6_fill_record,
    make_bit_reader,
    make_chunk_stream,
    make_decoder_state,
    make_dll_literal_table_profile,
    make_dll_long_distance_table_profile,
    make_dll_short_distance_table_profile,
    make_literal_models,
    make_match_models,
    make_range_decoder,
    peek_bitknit_header_bits,
    probe_bitknit_chunk_fsm_entry,
    read_bitknit_header_signed_byte,
    read_section6_fill_from_header,
    seed_bitknit_state7_word_ranges,
    sign_extend,
    split_bitknit_extra_bits,
    make_zero_biased_literal_profile,
    make_word_stream,
    parse_bitknit_plan,
)
from io_scene_gr2.gr2.decompress.oodle0 import parse_oodle0_plan
from io_scene_gr2.gr2.decompress.research_native import DEFAULT_RESEARCH_LIB, ResearchNativeBackend
from io_scene_gr2.gr2.file import read_gr2
from io_scene_gr2.gr2.fixup import load_sections
from io_scene_gr2.gr2.animation import extract_animation_set, sample_curve_values
from io_scene_gr2.gr2.geometry import extract_mesh_geometries
from io_scene_gr2.gr2.material import extract_materials
from io_scene_gr2.gr2.skeleton import extract_skeletons
from io_scene_gr2.gr2.texture import resolve_texture_path, texture_basename
from io_scene_gr2.gr2.types import summarize_meshes, summarize_root_object


try:
    import pytest
except Exception:  # pragma: no cover - manual runner fallback
    pytest = None


SAMPLE_ROOT = Path(os.environ.get("GR2_SAMPLE_ROOT", "__missing_gr2_sample_root__"))
YMIR_SAMPLE_ROOT = Path(os.environ.get("GR2_YMIR_SAMPLE_ROOT", "__missing_gr2_ymir_root__"))
GENERATED_CODEC_ROOT = Path(os.environ.get("GR2_GENERATED_CODEC_ROOT", "__missing_gr2_generated_codec_root__"))


def require_file(path: Path) -> bool:
    if path.exists():
        return True
    if pytest is not None:
        pytest.skip(f"missing optional fixture: {path}")
    return False


def test_parse_oodle1_gryphon():
    path = SAMPLE_ROOT / "Granny Viewer" / "Gryphon.gr2"
    if not require_file(path):
        return
    gr2 = read_gr2(path)
    assert gr2.header.version == 6
    assert gr2.header.pointer_size == 32
    assert len(gr2.sections) == 8
    assert any(section.compression == COMPRESSION_OODLE1 for section in gr2.sections)


def test_oodle1_clean_backend_matches_known_hashes_when_available():
    path = SAMPLE_ROOT / "Granny Viewer" / "Gryphon.gr2"
    if not path.exists():
        return
    expected = {
        0: "43704a544ea3fa75c6fbde1d876e395526731dd0326c221b03b214ba22ee7bb4",
        1: "7df6e4d6346acf198eacf3c5eaafbb5d7bd8f77a15f5ec79f1c9015b7e282f56",
        2: "f53bda2d80df18ae5675edc7fa48ae41c4c4fc6ef6c1ac8c3eb043dd52f92090",
        6: "71b24d8eed6f84ab0d3571108334238185ad7bc6ee86e75039b44d51f3dc0706",
    }
    gr2 = read_gr2(path)
    for index, digest in expected.items():
        section = gr2.sections[index]
        data = decompress_section(section, gr2.section_bytes(section))
        assert hashlib.sha256(data).hexdigest() == digest


def test_parse_oodle0_granny_rocks():
    path = SAMPLE_ROOT / "Granny Viewer" / "GrannyRocks.gr2"
    if not require_file(path):
        return
    gr2 = read_gr2(path)
    assert gr2.header.version == 6
    assert len(gr2.sections) == 6
    assert sum(section.compression == COMPRESSION_OODLE0 for section in gr2.sections) == 5
    assert gr2.sections[-1].compression == COMPRESSION_NONE


def test_none_section_decompresses():
    path = SAMPLE_ROOT / "Granny Viewer" / "GrannyRocks.gr2"
    if not require_file(path):
        return
    gr2 = read_gr2(path)
    section = gr2.sections[-1]
    data = decompress_section(section, gr2.section_bytes(section))
    assert len(data) == section.expanded_size


def test_oodle0_header_plan():
    path = SAMPLE_ROOT / "Granny Viewer" / "GrannyRocks.gr2"
    if not require_file(path):
        return
    gr2 = read_gr2(path)
    section = gr2.sections[0]
    plan = parse_oodle0_plan(section, gr2.section_bytes(section))
    assert plan.bitstream_offset == 36
    assert [block.output_size for block in plan.blocks] == [1360376, 0, 13224]
    assert plan.blocks[0].header.max_byte_value == 256
    assert plan.blocks[0].header.max_offset == 262136
    assert plan.blocks[0].header.unique_byte_values == 256
    assert plan.blocks[0].header.unique_offsets == 2433
    assert plan.blocks[0].header.unique_length_contexts == (59, 17, 21, 60)


def test_oodle0_clean_backend_matches_known_hashes_when_available():
    path = SAMPLE_ROOT / "Granny Viewer" / "GrannyRocks.gr2"
    if not path.exists():
        return
    expected = {
        0: "5927c92a3c26f043e3d4666006c68c10cf00ab241c6243888ca8866a6970c8b2",
        1: "e555866abd0b7cf5b8592e61e5e9d00aaf6ba186172c78ff989dd8abf6677fa9",
        2: "eb91551a31cbe807155d0c1b7023c896a3a091c9ca0c5372379282aa3e955ea7",
        3: "9bcbb9dd5df90dee1cbfe7dcdbe5bd614193940157befe32c4a0dfb8c5ee6d77",
        4: "6be27601874b3ca35aeb7ec5cdc1076c4b294001c9c98a92d118b4de4a336f67",
    }
    gr2 = read_gr2(path)
    for index, digest in expected.items():
        section = gr2.sections[index]
        data = decompress_section(section, gr2.section_bytes(section))
        assert hashlib.sha256(data).hexdigest() == digest


def test_oodle0_granny_rocks_load_sections_when_available():
    path = SAMPLE_ROOT / "Granny Viewer" / "GrannyRocks.gr2"
    if not path.exists():
        return
    gr2 = read_gr2(path)
    loaded = load_sections(gr2)
    assert [len(section) for section in loaded.sections_original] == [
        1373600,
        136864,
        57084,
        183104,
        76128,
        855172,
    ]
    assert len(loaded.pointer_fixups) == 34820
    assert len(loaded.mixed_marshalling_fixups) == 9


def test_parse_bitknit2_ymir_sample_when_available():
    path = YMIR_SAMPLE_ROOT / "290325alin_frz_vafreacamarc.GR2"
    if not path.exists():
        return
    gr2 = read_gr2(path)
    assert gr2.header.version == 7
    assert sum(section.compression == COMPRESSION_BITKNIT2 for section in gr2.sections) == 7
    section = gr2.sections[0]
    plan = parse_bitknit_plan(section, gr2.section_bytes(section))
    assert plan.payload_offset == 48
    assert plan.header is not None
    assert plan.header.marker == BITKNIT2_MARKER
    assert plan.header.header_tag == 0x50
    assert make_word_stream(plan, gr2.section_bytes(section)).read_u32le() == 0xFFF1003C
    chunk = make_chunk_stream(plan, gr2.section_bytes(section)).read_chunk()
    assert chunk.offset == plan.payload_offset
    assert chunk.is_full
    assert len(chunk.data) == BITKNIT_CHUNK_SIZE
    assert chunk.words[0] == 0xFFF1003C
    range_decoder = make_range_decoder(plan, gr2.section_bytes(section))
    assert range_decoder.code == 0x1E
    assert range_decoder.span == BITKNIT_RANGE_INITIAL
    assert range_decoder.carry_bit == 0
    reader = make_bit_reader(plan, gr2.section_bytes(section))
    assert [reader.read_bits(4) for _ in range(4)] == [0xC, 0x3, 0x0, 0x0]
    state = make_decoder_state(plan, gr2.section_bytes(section))
    assert state.context_index(0) == 0
    assert state.context_index(7) == 3
    assert state.literal_model(4) is state.literal_models[0]
    assert state.match_model(7) is state.match_models[3]


def test_bitknit2_clean_backend_decodes_supported_prefix_when_available():
    path = YMIR_SAMPLE_ROOT / "290325alin_frz_vafreacamarc.GR2"
    if not path.exists():
        return
    gr2 = read_gr2(path)
    section = gr2.sections[0]
    data = decompress_section(section, gr2.section_bytes(section))
    assert len(data) == section.expanded_size
    assert data[:13] == b"\x00" * 12 + b"\x03"


def test_bitknit_adaptive_model_updates_and_rescales():
    model = BitKnitAdaptiveModel(4, rebuild_interval=2)
    assert model.total == 4
    assert model.lookup(0).symbol == 0
    assert model.lookup(3).symbol == 3
    model.update(2)
    updated = model.range_for(2)
    assert updated.high - updated.low == 1 + BITKNIT_MODEL_UPDATE
    assert model.total == 4 + BITKNIT_MODEL_UPDATE
    model.update(2)
    assert model.countdown == 2
    assert model.range_for(2).high - model.range_for(2).low == 32


def test_bitknit_adaptive_model_take_updates():
    model = BitKnitAdaptiveModel(4, rebuild_interval=4)
    decoded = model.take(2)
    assert decoded.symbol == 2
    assert model.range_for(2).high - model.range_for(2).low == 32
    assert model.countdown == 3


def test_bitknit_adaptive_model_accepts_initial_weights():
    model = BitKnitAdaptiveModel(4, initial_weights=(1, 3, 1, 1))
    assert model.total == 6
    assert model.lookup(1).symbol == 1
    assert model.lookup(3).symbol == 1
    assert model.range_for(1).high - model.range_for(1).low == 3


def test_bitknit_range_decoder_normalizes_first_payload_bytes():
    payload = bytes.fromhex("3c00f1ff298242ff")
    decoder = BitKnitRangeDecoder.from_payload(payload, 0)
    decoder.normalize()
    assert decoder.code == 0x1E0078FF
    assert decoder.span == 0x80000000
    assert decoder.carry_bit == 1
    assert decoder.byte_offset == 4
    assert decoder.span > BITKNIT_RANGE_NORMALIZE_LIMIT
    assert decoder.peek(BITKNIT_LITERAL_SYMBOLS) == 121
    assert decoder.peek(BITKNIT_MATCH_SYMBOLS) == 16


def test_bitknit_range_decoder_take_updates_interval():
    payload = bytes.fromhex("3c00f1ff298242ff")
    decoder = BitKnitRangeDecoder.from_payload(payload, 0)
    model = BitKnitAdaptiveModel(BITKNIT_LITERAL_SYMBOLS)
    decoded = decoder.take_from_model(model)
    assert decoded.symbol == 121
    assert decoder.code == 0x000B5DD3
    assert decoder.span == 0x003F618C
    assert model.range_for(121).high - model.range_for(121).low == 32


def test_bitknit_range_decoder_dll_style_take_helpers():
    payload = bytes.fromhex("3c00f1ff298242ff")

    decoder = BitKnitRangeDecoder.from_payload(payload, 0)
    assert decoder.take_uniform(BITKNIT_LITERAL_SYMBOLS) == 121
    assert decoder.code == 0x000B5DD3
    assert decoder.span == 0x003F618C
    assert decoder.scale == 0x003F618C

    shifted = BitKnitRangeDecoder.from_payload(payload, 0)
    assert shifted.take_shifted(8, 0x100) == 60
    assert shifted.code == 0x000078FF
    assert shifted.span == 0x00800000
    assert shifted.scale == 0x00800000

    manual = BitKnitRangeDecoder.from_payload(payload, 0)
    manual.take(BitKnitSymbolRange(symbol=121, low=121, high=122, total=BITKNIT_LITERAL_SYMBOLS))
    scaled = BitKnitRangeDecoder.from_payload(payload, 0)
    scaled.take_scaled_range(121, 1, BITKNIT_LITERAL_SYMBOLS)
    assert (scaled.code, scaled.span, scaled.scale) == (manual.code, manual.span, manual.scale)


def test_bitknit_model_sets_have_four_contexts():
    literal_models = make_literal_models()
    match_models = make_match_models()
    assert len(literal_models) == 4
    assert len(match_models) == 4
    assert all(model.symbol_count == BITKNIT_LITERAL_SYMBOLS for model in literal_models)
    assert all(model.symbol_count == BITKNIT_MATCH_SYMBOLS for model in match_models)


def test_bitknit_model_profile_weights_apply_to_all_contexts():
    profile = BitKnitModelProfile(
        literal_weights=(2,) + (1,) * (BITKNIT_LITERAL_SYMBOLS - 1),
        match_weights=(3,) + (1,) * (BITKNIT_MATCH_SYMBOLS - 1),
    )
    literal_models = make_literal_models(profile)
    match_models = make_match_models(profile)
    assert all(model.range_for(0).high - model.range_for(0).low == 2 for model in literal_models)
    assert all(model.range_for(0).high - model.range_for(0).low == 3 for model in match_models)


def test_bitknit_zero_biased_profile():
    profile = make_zero_biased_literal_profile(3985)
    literal_models = make_literal_models(profile)
    assert literal_models[0].range_for(0).high == 3985
    assert literal_models[0].total == 4501


def test_bitknit_decoder_state_takes_context_symbols():
    path = YMIR_SAMPLE_ROOT / "290325alin_frz_vafreacamarc.GR2"
    if not path.exists():
        return
    gr2 = read_gr2(path)
    section = gr2.sections[0]
    plan = parse_bitknit_plan(section, gr2.section_bytes(section))
    state = make_decoder_state(plan, gr2.section_bytes(section))
    literal = state.take_literal_symbol(4, 3)
    match = state.take_match_symbol(7, 2)
    assert literal.symbol == 3
    assert match.symbol == 2
    assert state.literal_models[0].range_for(3).high - state.literal_models[0].range_for(3).low == 32
    assert state.match_models[3].range_for(2).high - state.match_models[3].range_for(2).low == 32


def test_bitknit_decoder_state_decodes_first_uniform_literal_symbol():
    path = YMIR_SAMPLE_ROOT / "290325alin_frz_vafreacamarc.GR2"
    if not path.exists():
        return
    gr2 = read_gr2(path)
    section = gr2.sections[0]
    plan = parse_bitknit_plan(section, gr2.section_bytes(section))
    state = make_decoder_state(plan, gr2.section_bytes(section))
    decoded = state.decode_literal_symbol(0)
    assert decoded.symbol == 121
    assert state.literal_models[0].range_for(121).high - state.literal_models[0].range_for(121).low == 32
    assert state.range_decoder.code == 0x000B5DD3
    assert state.range_decoder.span == 0x003F618C


def test_bitknit_decoder_state_decodes_zero_biased_control_token():
    path = YMIR_SAMPLE_ROOT / "290325alin_frz_vafreacamarc.GR2"
    if not path.exists():
        return
    gr2 = read_gr2(path)
    section = gr2.sections[0]
    plan = parse_bitknit_plan(section, gr2.section_bytes(section))
    state = make_decoder_state(
        plan,
        gr2.section_bytes(section),
        make_zero_biased_literal_profile(3985),
    )
    token = None
    for offset in range(13):
        token = state.decode_literal_token(offset)
    assert token is not None
    assert token.symbol == 516
    assert token.kind.name == "match"
    assert token.kind.needs_extra_bits
    token_dict = token.to_dict()
    assert token_dict["offset"] == 12
    assert token_dict["match"]["index"] == 228


def test_bitknit_symbol_classification():
    assert classify_bitknit_symbol(0).name == "literal"
    assert classify_bitknit_symbol(0xFF).name == "literal"
    assert classify_bitknit_symbol(0x100).name == "match"
    assert not classify_bitknit_symbol(0x100).needs_extra_bits
    assert classify_bitknit_symbol(BITKNIT_EXTRA_MATCH_BASE).needs_extra_bits
    assert describe_match_symbol(0) is None
    short_match = describe_match_symbol(0x100)
    assert short_match is not None
    assert short_match.index == 0
    assert not short_match.needs_extra_bits
    extra_match = describe_match_symbol(516)
    assert extra_match is not None
    assert extra_match.index == 228
    assert extra_match.needs_extra_bits
    control = describe_control_symbol(516)
    assert control is not None
    assert control.index == 228
    assert control.low5 == 4
    assert control.group == 7
    recent = describe_distance_symbol(7)
    assert recent.is_recent
    assert recent.recent_index == 7
    direct = describe_distance_symbol(BITKNIT_RECENT_DISTANCE_COUNT + 228)
    assert not direct.is_recent
    assert direct.direct_index == 228
    assert direct.low5 == 4
    assert direct.group == 3
    assert direct.needs_extra_bits
    assert describe_direct_distance_symbols(8, 0).distance == 1
    assert describe_direct_distance_symbols(39, 0).distance == 32
    assert describe_direct_distance_symbols(8, 1, 0).distance == 33
    assert describe_direct_distance_symbols(39, 1, 1).distance == 96
    tier = describe_direct_distance_symbols(8, 4, 15)
    assert tier.extra_bits == 4
    assert tier.extra_value == 15
    assert tier.distance == 961
    short_extra = split_bitknit_extra_bits(0x1234, 12)
    assert [(record.low, record.tag, record.bit_count) for record in short_extra] == [
        (0x234, 0x800C, 12)
    ]
    long_extra = split_bitknit_extra_bits(0x12345, 17)
    assert [(record.low, record.tag, record.bit_count) for record in long_extra] == [
        (0x1, 0x8001, 1),
        (0x2345, 0xC000, 16),
    ]
    assert describe_length_symbol(0x100).length == 2
    assert describe_length_symbol(0x11F).length == 33
    extended = describe_length_symbol(0x120, extra_value=1)
    assert extended.extra_bits == 1
    assert extended.length == 35


def test_bitknit_dll_table_profiles():
    literal = make_dll_literal_table_profile()
    assert len(literal.weights) == 0x12C
    assert literal.update_weight == 0x2D5
    assert literal.rebuild_interval == 0x400
    assert literal.cumulative[:5] == (0, 123, 247, 371, 495)
    assert literal.cumulative[263:266] == (32608, 32732, 32733)
    assert literal.cumulative[-1] == 0x8000

    short_distance = make_dll_short_distance_table_profile()
    assert len(short_distance.weights) == 0x15
    assert short_distance.update_weight == 0x3EC
    assert short_distance.cumulative[:5] == (0, 1560, 3120, 4681, 6241)

    long_distance = make_dll_long_distance_table_profile()
    assert len(long_distance.weights) == 0x28
    assert long_distance.update_weight == 0x3D9
    assert long_distance.cumulative[:5] == (0, 819, 1638, 2457, 3276)


def test_bitknit_dll_adaptive_model_rebuilds_on_countdown():
    profile = make_dll_long_distance_table_profile()
    model = BitKnitDllAdaptiveModel(profile)
    for _ in range(profile.rebuild_interval - 1):
        model.update(0)
    assert model.countdown == 1
    assert model.cumulative == list(profile.cumulative)
    model.update(0)
    assert model.countdown == profile.rebuild_interval
    assert model.cumulative[1] > profile.cumulative[1]
    assert model.weights == [1] * len(model.weights)


def test_bitknit_dll_word_range_decoder():
    profile = make_dll_long_distance_table_profile()
    decoded = lookup_dll_table_symbol(profile, 818)
    assert decoded.symbol == 0
    assert decoded.low == 0
    assert decoded.high == 819
    assert lookup_dll_table_symbol(profile, 819).symbol == 1

    decoder = BitKnitWordRangeDecoder(b"\x34\x12", 0, 0x8000)
    decoder.take(decoded)
    assert decoder.window == 0x03331234
    assert decoder.word_offset == 2


def test_bitknit_state7_seed_helper():
    data = bytes.fromhex("0100 0000 3412 7856 9abc")
    seed = seed_bitknit_state7_word_ranges(data, 0)
    assert seed.initial_word == 0x00010000
    assert seed.primary_window == 0x10001234
    assert seed.extra_bits == 16
    assert seed.range_window == 0x10001234
    assert seed.extra_window == 0x00015678
    assert seed.input_offset == 8

    data = bytes.fromhex("3412 cdab 7856 9abc")
    seed = seed_bitknit_state7_word_ranges(data, 0)
    assert seed.initial_word == 0x1234ABCD
    assert seed.primary_window == 0x01234ABC
    assert seed.extra_bits == 29
    assert seed.range_window == 0x091A5678
    assert seed.extra_window == 0x2ABCBC9A
    assert seed.input_offset == 8


def test_bitknit_state7_shared_window_decoder():
    decoder = BitKnitState7WindowDecoder(bytes.fromhex("3412 7856"), 0, 0x8000, 0x20)

    assert decoder.read_extra_bits(5) == 0
    assert decoder.extra_window == 0x00011234
    assert decoder.word_offset == 2

    decoded = lookup_dll_table_symbol(make_dll_long_distance_table_profile(), 0)
    decoder.take_range(decoded)
    assert decoder.word_offset == 4
    assert decoder.range_window == 0x03335678

    decoder = BitKnitState7WindowDecoder(b"\x34\x12", 0, 0x8000, 0xAABBCCDD)
    decoded = lookup_dll_table_symbol(make_dll_long_distance_table_profile(), 0)
    decoder.take_swapped_from_dll_profile(make_dll_long_distance_table_profile())
    assert decoded.symbol == 0
    assert decoder.range_window == 0xAABBCCDD
    assert decoder.extra_window == 0x03331234

    decoder = BitKnitState7WindowDecoder(b"\x78\x56", 0, 0x21, 0xAABBCCDD)
    assert decoder.read_swapped_extra_bits(1) == 1
    assert decoder.range_window == 0xAABBCCDD
    assert decoder.extra_window == 0x00105678


def test_bitknit_state7_initial_literal_swap():
    data = bytes.fromhex("0100 0000 3412 7856 9abc")
    seed = seed_bitknit_state7_word_ranges(data, 0)
    literal, decoder = make_state7_decoder_after_initial_literal(data, seed)
    assert literal == 0x34
    assert decoder.range_window == seed.extra_window
    assert decoder.extra_window == 0x00100012
    assert decoder.word_offset == 8


def test_bitknit_recent_distance_state():
    recent = BitKnitRecentDistanceState.initial()
    distance, slot = recent.take_recent(0)
    assert distance == 1
    assert slot == (BITKNIT_INITIAL_RECENT_SELECTOR & 7)
    assert recent.selector == BITKNIT_INITIAL_RECENT_SELECTOR
    source_slot, target_slot = recent.insert_direct(8)
    assert (source_slot, target_slot) == (6, 7)
    assert recent.distances[6] == 8
    assert recent.distances[7] == 1


def test_bitknit_state7_prefix_matches_cached_oracle_when_available():
    path = YMIR_SAMPLE_ROOT / "290325alin_frz_vafreacamarc.GR2"
    oracle_root = Path("research_artifacts") / "bitknit_dll_probe"
    oracle_paths = {
        index: oracle_root / f"290325alin_frz_vafreacamarc.section{index}.dll.bin"
        for index in (0, 3, 4, 6)
    }
    if not path.exists() or not all(oracle_path.exists() for oracle_path in oracle_paths.values()):
        return
    gr2 = read_gr2(path)
    for index, oracle_path in oracle_paths.items():
        section = gr2.sections[index]
        result = decode_bitknit_state7_prefix(
            gr2.section_bytes(section),
            section.expanded_size,
            max_output_size=4096,
            max_steps=50000,
        )
        assert result.output == oracle_path.read_bytes()[:4096]
        assert result.stopped is None


def test_bitknit2_section0_decompresses_when_available():
    path = YMIR_SAMPLE_ROOT / "290325alin_frz_vafreacamarc.GR2"
    if not path.exists():
        return
    gr2 = read_gr2(path)
    section = gr2.sections[0]
    data = decompress_section(section, gr2.section_bytes(section))
    assert len(data) == section.expanded_size
    assert data[:32] == bytes.fromhex(
        "00 00 00 00 00 00 00 00 00 00 00 00 03 00 00 00"
        " 00 00 00 00 06 00 00 00 00 00 00 00 01 00 00 00"
    )


def test_bitknit2_native_supported_sections_match_known_hashes_when_available():
    path = YMIR_SAMPLE_ROOT / "290325alin_frz_vafreacamarc.GR2"
    if not path.exists():
        return
    expected = {
        0: "ba9d4da6c28d8e482b9f5e13f1e7172677d4341df0f8ca45262207d71750f7fb",
        1: "97e8ddd89cf9c1a304e1f5d73e70f6d07a026760785b6fc970aa5ef6f16eae22",
        2: "778810305aa259453bcd99d3a87abd40291d6072dbe2525ceb46e9bd93f06b0f",
        3: "ef03f49816290ffdb32d737b1da7a4d4508ceeba6a6bf8882af5114bf24be5ec",
        4: "3ab52a1bee394801b45e5f11f3d42ad9d70209b647da6143cabb3ac4f72ce14d",
        6: "9804f0d40ee5da4cf97a754479930545638c474f846591b22f2fa67ffb9280dd",
    }
    gr2 = read_gr2(path)
    for index, digest in expected.items():
        section = gr2.sections[index]
        data = decompress_section(section, gr2.section_bytes(section))
        assert hashlib.sha256(data).hexdigest() == digest


def test_bitknit_classic_generated_supported_sections_when_available():
    path = GENERATED_CODEC_ROOT / "Gryphon_bitknit.gr2"
    if not path.exists():
        return
    expected = {
        0: "f7406dd960623ea36947a8a1ce6410a1cf54582c3a2c93059ab6fed917f4f350",
        1: "7df6e4d6346acf198eacf3c5eaafbb5d7bd8f77a15f5ec79f1c9015b7e282f56",
        2: "f53bda2d80df18ae5675edc7fa48ae41c4c4fc6ef6c1ac8c3eb043dd52f92090",
        5: "0d38eb8499b7a36e1be5044c9af387dc444e13400e14f94a179b6b3b3f84df2b",
        6: "b9414de8a2ec85cd0b06fb803ea544cffbdfdaaa94320cab11679f32ae0890a8",
    }
    gr2 = read_gr2(path)
    for index, digest in expected.items():
        section = gr2.sections[index]
        data = decompress_section(section, gr2.section_bytes(section))
        assert hashlib.sha256(data).hexdigest() == digest


def test_bitknit2_generated_supported_sections_when_available():
    path = GENERATED_CODEC_ROOT / "Gryphon_bitknit2.gr2"
    if not path.exists():
        return
    expected = {
        0: "f7406dd960623ea36947a8a1ce6410a1cf54582c3a2c93059ab6fed917f4f350",
        1: "7df6e4d6346acf198eacf3c5eaafbb5d7bd8f77a15f5ec79f1c9015b7e282f56",
        2: "f53bda2d80df18ae5675edc7fa48ae41c4c4fc6ef6c1ac8c3eb043dd52f92090",
        5: "0d38eb8499b7a36e1be5044c9af387dc444e13400e14f94a179b6b3b3f84df2b",
        6: "b9414de8a2ec85cd0b06fb803ea544cffbdfdaaa94320cab11679f32ae0890a8",
    }
    gr2 = read_gr2(path)
    for index, digest in expected.items():
        section = gr2.sections[index]
        data = decompress_section(section, gr2.section_bytes(section))
        assert hashlib.sha256(data).hexdigest() == digest


def test_bitknit2_compressed_fixups_load_primary_mesh_when_available():
    path = YMIR_SAMPLE_ROOT / "290325alin_frz_vafreacamarc.GR2"
    if not path.exists():
        return
    gr2 = read_gr2(path)
    backend = ResearchNativeBackend(DEFAULT_RESEARCH_LIB) if DEFAULT_RESEARCH_LIB.exists() else None
    loaded = load_sections(gr2, backend=backend)
    geometries = extract_mesh_geometries(loaded)
    skeletons = extract_skeletons(loaded)
    assert len(loaded.pointer_fixups) == 1052
    assert len(loaded.mixed_marshalling_fixups) == 1
    assert len(geometries) == 2
    assert sum(len(geometry.positions) for geometry in geometries) == 11915
    assert sum(len(geometry.triangles) for geometry in geometries) == 22847
    assert sum(len(skeleton.bones) for skeleton in skeletons) == 90


def test_blender_importer_uses_clean_section_loader():
    source = (Path(__file__).resolve().parents[1] / "io_scene_gr2" / "__init__.py").read_text()
    execute_body = source[source.index("        def execute(self, context):") :]
    execute_body = execute_body[: execute_body.index("    def menu_func_import")]
    assert "load_sections(gr2_file)" in execute_body
    assert "ResearchNativeBackend" not in execute_body
    assert "DEFAULT_RESEARCH_LIB" not in execute_body
    assert "animation_filepath" in execute_body
    assert "extract_animation_set(animation_loaded)" in execute_body
    assert "_create_animation_actions(animation_set, armatures, context.scene)" in source
    assert "_insert_static_pose_keys(" in source
    assert "_track_pose_basis_samples(" in source
    assert "_to_pose_basis_transform(" in source
    assert "sample_curve_values(track.orientation, duration, time_step)" in source
    assert 'point.interpolation = "LINEAR"' in source
    assert 'fcurve.extrapolation = "CONSTANT"' in source
    assert "scene.frame_end = max_frame" in source


def test_raw_writer_round_trips_minimal_mesh(tmp_path):
    from io_scene_gr2.gr2.export import ExportMesh, ExportScene, ExportVertex
    from io_scene_gr2.gr2.write import write_raw_gr2

    scene = ExportScene(
        meshes=(
            ExportMesh(
                name="Triangle",
                vertices=(
                    ExportVertex((0.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0), ()),
                    ExportVertex((1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (1.0, 1.0), ()),
                    ExportVertex((0.0, 1.0, 0.0), (0.0, 0.0, 1.0), (0.0, 0.0), ()),
                ),
                indices=(0, 1, 2),
                material_names=("Body",),
                material_indices=(0,),
                material_texture_files=("textures/body.dds",),
                material_texture_sizes=((256, 128),),
            ),
        ),
        skeletons=(),
    )
    path = write_raw_gr2(tmp_path / "triangle.gr2", scene)
    gr2 = read_gr2(path)
    assert gr2.header.crc == zlib.crc32(path.read_bytes()[32 + gr2.header.section_array_offset:]) & 0xFFFFFFFF
    geometries = extract_mesh_geometries(load_sections(read_gr2(path)))
    assert len(geometries) == 1
    assert geometries[0].name == "Triangle"
    assert geometries[0].positions == tuple(vertex.position for vertex in scene.meshes[0].vertices)
    assert geometries[0].normals == tuple(vertex.normal for vertex in scene.meshes[0].vertices)
    assert geometries[0].uvs == tuple(vertex.uv for vertex in scene.meshes[0].vertices)
    assert geometries[0].triangles == ((0, 1, 2),)
    assert geometries[0].materials[0].name == "Body"
    assert geometries[0].materials[0].texture_file == "textures/body.dds"
    assert geometries[0].materials[0].texture_size == (256, 128)
    assert geometries[0].triangle_groups[0].material_index == 0
    material = extract_materials(load_sections(read_gr2(path)))[0]
    assert material.name == "Body"
    assert material.texture_file == "textures/body.dds"
    root = summarize_root_object(load_sections(read_gr2(path)), max_arrays=8)
    root_fields = {field["name"]: field for field in root["fields"]}
    assert root_fields["Textures"]["count"] == 1
    assert root_fields["VertexDatas"]["count"] == 1
    assert root_fields["TriTopologies"]["count"] == 1
    assert root_fields["Models"]["count"] == 1
    assert root_fields["TrackGroups"]["count"] == 0
    assert root_fields["Animations"]["count"] == 0


def test_raw_writer_round_trips_skeleton_and_weights(tmp_path):
    from io_scene_gr2.gr2.export import (
        ExportBone,
        ExportMesh,
        ExportScene,
        ExportSkeleton,
        ExportVertex,
        ExportVertexWeight,
    )
    from io_scene_gr2.gr2.write import write_raw_gr2

    identity = (
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 0.0,
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 1.0,
    )
    child = (
        1.0, 0.0, 0.0, 0.0,
        0.0, 1.0, 0.0, 2.0,
        0.0, 0.0, 1.0, 0.0,
        0.0, 0.0, 0.0, 1.0,
    )
    scene = ExportScene(
        meshes=(
            ExportMesh(
                name="WeightedTriangle",
                vertices=(
                    ExportVertex((0.0, 0.0, 0.0), (0.0, 0.0, 1.0), (0.0, 1.0), (ExportVertexWeight("Root", 1.0),)),
                    ExportVertex((1.0, 0.0, 0.0), (0.0, 0.0, 1.0), (1.0, 1.0), (ExportVertexWeight("Child", 1.0),)),
                    ExportVertex((0.0, 1.0, 0.0), (0.0, 0.0, 1.0), (0.0, 0.0), (ExportVertexWeight("Root", 0.25), ExportVertexWeight("Child", 0.75))),
                ),
                indices=(0, 1, 2),
                material_names=("Skin", "Metal"),
                material_indices=(0,),
            ),
        ),
        skeletons=(
            ExportSkeleton(
                name="Rig",
                bones=(
                    ExportBone("Root", "", identity, granny_rest_local=identity, inverse_world_transform=identity),
                    ExportBone("Child", "Root", child, granny_rest_local=child, inverse_world_transform=identity),
                ),
            ),
        ),
    )
    path = write_raw_gr2(tmp_path / "weighted.gr2", scene)
    loaded = load_sections(read_gr2(path))
    geometries = extract_mesh_geometries(loaded)
    skeletons = extract_skeletons(loaded)
    assert [bone.name for bone in skeletons[0].bones] == ["Root", "Child"]
    assert skeletons[0].bones[1].parent_index == 0
    assert skeletons[0].bones[1].transform.position == (0.0, 2.0, 0.0)
    assert skeletons[0].bones[1].inverse_world_transform == identity
    assert geometries[0].bone_bindings[0].name == "Root"
    assert geometries[0].bone_bindings[1].name == "Child"
    assert geometries[0].vertex_weights[0][0].bone_index == 0
    assert geometries[0].vertex_weights[1][0].bone_index == 1


def test_raw_writer_uses_32bit_indices_when_needed(tmp_path):
    from io_scene_gr2.gr2.export import ExportMesh, ExportScene, ExportVertex
    from io_scene_gr2.gr2.write import write_raw_gr2

    vertices = tuple(
        ExportVertex((float(index), 0.0, 0.0), (0.0, 0.0, 1.0), None, ())
        for index in range(0x10001)
    )
    scene = ExportScene(
        meshes=(
            ExportMesh(
                name="WideMesh",
                vertices=vertices,
                indices=(0, 1, 0x10000),
                material_names=(),
            ),
        ),
        skeletons=(),
    )
    geometry = extract_mesh_geometries(load_sections(read_gr2(write_raw_gr2(tmp_path / "wide.gr2", scene))))[0]
    assert geometry.vertex_count == 0x10001
    assert geometry.index_count == 3
    assert geometry.triangles == ((0, 1, 0x10000),)


def test_animation_metadata_pixo_run_when_available():
    path = SAMPLE_ROOT / "Granny-3D-SDK-main" / "tutorials" / "media" / "pixo_run.gr2"
    if not path.exists():
        return
    loaded = load_sections(read_gr2(path))
    animation_set = extract_animation_set(loaded)
    assert len(animation_set.track_groups) == 1
    assert len(animation_set.animations) == 1
    track_group = animation_set.track_groups[0]
    assert track_group.name == "grannyRootBone"
    assert track_group.vector_track_count == 8
    assert track_group.transform_track_count == 119
    assert track_group.vector_track_names[:2] == ("L_footLock", "R_footLock")
    assert track_group.transform_tracks[0].name == "Chest"
    assert track_group.transform_tracks[0].orientation.codec == "D4Constant32f"
    assert len(track_group.transform_tracks[0].orientation.sample_value) == 4
    assert track_group.transform_tracks[0].position.codec == "D3I1K16uC16u"
    assert track_group.transform_tracks[0].position.knot_control_count == 78
    assert len(track_group.transform_tracks[0].position.knot_values) == 39
    assert len(track_group.transform_tracks[0].position.control_values) == 39
    assert track_group.transform_tracks[0].scale_shear.sample_value == (
        1.0,
        0.0,
        0.0,
        0.0,
        1.0,
        0.0,
        0.0,
        0.0,
        1.0,
    )
    assert track_group.transform_tracks[1].orientation.codec == "D4nK8uC7u"
    assert len(track_group.transform_tracks[1].orientation.knot_values) == 20
    assert len(track_group.transform_tracks[1].orientation.control_values) == 20
    assert track_group.transform_tracks[1].position.codec == "D3K16uC16u"
    assert track_group.transform_tracks[1].position.knot_control_count == 260
    assert len(track_group.transform_tracks[1].position.knot_values) == 65
    assert len(track_group.transform_tracks[1].position.control_values) == 65
    _, samples = sample_curve_values(
        track_group.transform_tracks[1].orientation,
        animation_set.animations[0].duration,
        animation_set.animations[0].time_step,
    )
    assert len(samples) == 145
    assert round(sum(value * value for value in samples[0]), 6) == 1.0
    assert track_group.transform_tracks[2].position.codec == "D3Constant32f"
    assert len(track_group.transform_tracks[2].position.sample_value) == 3
    animation = animation_set.animations[0]
    assert round(animation.duration, 3) == 1.2
    assert round(animation.time_step, 6) == 0.008333
    assert animation.track_group_names == ("grannyRootBone",)


def test_animation_metadata_pixo_dance_when_available():
    path = SAMPLE_ROOT / "Granny-3D-SDK-main" / "tutorials" / "media" / "pixo_dance.gr2"
    if not path.exists():
        return
    loaded = load_sections(read_gr2(path))
    animation_set = extract_animation_set(loaded)
    assert len(animation_set.track_groups) == 2
    assert len(animation_set.animations) == 1
    assert [item.name for item in animation_set.track_groups] == ["pixo:ball", "pixo:root"]
    assert [item.transform_track_count for item in animation_set.track_groups] == [2, 248]
    assert animation_set.track_groups[0].transform_tracks[0].orientation.codec == "D4nK16uC15u"
    assert len(animation_set.track_groups[0].transform_tracks[0].orientation.knot_values) == 91
    assert len(animation_set.track_groups[0].transform_tracks[0].orientation.control_values) == 91
    assert round(animation_set.animations[0].duration, 3) == 33.967
    assert animation_set.animations[0].track_group_names == ("pixo:ball", "pixo:root")


def test_animation_metadata_metin_legacy_curve_when_available():
    path = (
        YMIR_SAMPLE_ROOT
        / "Unpacked client 23.3.4.0 Metin2 Ro Official Full pana in octombrie 2023 (are tot)"
        / "Unpacked client 23.2.5.0"
        / "d_"
        / "ymir work"
        / "pc2"
        / "assassin"
        / "general"
        / "wait_1.gr2"
    )
    if not path.exists():
        return
    animation_set = extract_animation_set(load_sections(read_gr2(path)))
    assert animation_set.track_groups[0].name == "Bip01"
    assert animation_set.track_groups[0].transform_track_count == 90
    track = animation_set.track_groups[0].transform_tracks[0]
    assert track.orientation.codec == "LegacyCurve32f"
    assert track.orientation.dimension == 4
    assert len(track.orientation.knot_values) == 64
    assert track.position.codec == "LegacyCurve32f"
    assert track.position.dimension == 3


def test_bitknit_chunk_fsm_entry_probe_when_available():
    path = YMIR_SAMPLE_ROOT / "290325alin_frz_vafreacamarc.GR2"
    if not path.exists():
        return
    gr2 = read_gr2(path)
    section = gr2.sections[0]
    checkpoint = probe_bitknit_chunk_fsm_entry(gr2.section_bytes(section))
    assert checkpoint.marker == BITKNIT2_MARKER
    assert checkpoint.state == 7
    assert checkpoint.input_offset == 2
    assert checkpoint.block_word == 0x50
    assert checkpoint.uses_compressed_handler


def test_bitknit_output_window_literals_and_matches():
    window = BitKnitOutputWindow(12)
    for value in (1, 2, 3, 4):
        window.append_literal_delta(value)
    assert window.context_index() == 0
    for value in (1, 1, 1, 1):
        window.append_literal_delta(value)
    assert bytes(window.data) == b"\x01\x02\x03\x04\x02\x03\x04\x05"
    window.copy_match(distance=4, length=4)
    assert window.finish() == b"\x01\x02\x03\x04\x02\x03\x04\x05\x02\x03\x04\x05"

    window = BitKnitOutputWindow(4)
    window.append_literal_from_distance(3, 1)
    window.copy_match(distance=1, length=2)
    window.append_literal_from_distance(3, 3)
    assert window.finish() == b"\x03\x03\x03\x06"


def test_bitknit_header_bit_reader_and_section6_fill_probe():
    assert sign_extend(0x7F, 8) == 127
    assert sign_extend(0x80, 8) == -128
    data = bytes([0b1010_1100, 0b0000_0011])
    assert peek_bitknit_header_bits(data, 2, 6, 2) == 0b101011
    reader = BitKnitHeaderBitReader(data, 2, 2)
    assert reader.read_bits(6) == 0b101011
    assert reader.bit_offset == 8
    assert make_section6_fill_record(0, 4) == b"\x02\x00\x00\x00"
    assert make_section6_fill_record(4, 4) == b"\x06\x04\x04\x04"
    assert make_section6_fill_record(-2, 4) == b"\x00\xfe\xfe\xfe"
    assert BITKNIT_SECTION6_RECORD_SIZE == 32


def test_bitknit_section6_header_fill_offsets_when_available():
    samples = [
        (YMIR_SAMPLE_ROOT / "290325alin_frz_vafreacamarc.GR2", 38),
        (
            YMIR_SAMPLE_ROOT
            / "Unpacked client 23.3.4.0 Metin2 Ro Official Full pana in octombrie 2023 (are tot)"
            / "Unpacked client 23.2.5.0"
            / "d_"
            / "ymir work"
            / "npc2"
            / "treasure_hunt_goblin"
            / "front_damage.gr2",
            48,
        ),
        (
            YMIR_SAMPLE_ROOT
            / "Unpacked client 23.3.4.0 Metin2 Ro Official Full pana in octombrie 2023 (are tot)"
            / "Unpacked client 23.2.5.0"
            / "d_"
            / "ymir work"
            / "npc2"
            / "treasure_hunt_goblin"
            / "front_dead.gr2",
            52,
        ),
    ]
    for path, fill_bit_offset in samples:
        if not path.exists():
            continue
        gr2 = read_gr2(path)
        section = gr2.sections[6]
        compressed = gr2.section_bytes(section)
        plan = parse_bitknit_plan(section, compressed)
        reader = make_header_bit_reader(plan, compressed, fill_bit_offset)
        assert reader.read_bits(8) == 2
        assert read_bitknit_header_signed_byte(compressed, fill_bit_offset) == 2
        assert read_section6_fill_from_header(compressed, fill_bit_offset) == 0
        assert decode_section6_fill_record_from_header(compressed, fill_bit_offset, 16) == (
            b"\x02" + b"\x00" * 15
        )
        assert decode_section6_initial_fill_records_from_header(compressed, fill_bit_offset) == (
            (b"\x02" + b"\x00" * (BITKNIT_SECTION6_RECORD_SIZE - 1))
            * BITKNIT_SECTION6_INITIAL_FILL_RECORDS
        )
        assert make_section6_fill_record(0)[:16] == b"\x02" + b"\x00" * 15
        candidates = find_section6_fill_candidates(compressed, b"\x02" + b"\x00" * 15)
        assert any(candidate.bit_offset == fill_bit_offset for candidate in candidates)
        selected = find_section6_control_fill_candidate(compressed, b"\x02" + b"\x00" * 15)
        assert selected is not None
        assert selected.bit_offset == fill_bit_offset


def test_missing_file():
    try:
        read_gr2(SAMPLE_ROOT / "missing.gr2")
    except FileNotFoundError:
        return
    raise AssertionError("expected FileNotFoundError")


def test_research_native_root_summary_when_available():
    if not DEFAULT_RESEARCH_LIB.exists():
        return
    path = SAMPLE_ROOT / "Granny Viewer" / "Gryphon.gr2"
    gr2 = read_gr2(path)
    loaded = load_sections(gr2, ResearchNativeBackend())
    summary = summarize_root_object(loaded)
    assert summary["member_count"] >= 10
    names = {field["name"] for field in summary["fields"]}
    assert {"ArtToolInfo", "ExporterInfo", "Meshes"}.issubset(names)


def test_research_native_mesh_summary_when_available():
    if not DEFAULT_RESEARCH_LIB.exists():
        return
    path = SAMPLE_ROOT / "Granny Viewer" / "Gryphon.gr2"
    gr2 = read_gr2(path)
    loaded = load_sections(gr2, ResearchNativeBackend())
    summary = summarize_meshes(loaded)
    assert summary["count"] == 1
    mesh = summary["meshes"][0]
    assert mesh["name"] == "polySurfaceShape82"
    assert mesh["vertex_components"] == ["Position", "Normal", "map1"]
    vertex_fields = {field["name"]: field for field in mesh["primary_vertex_data"]["fields"]}
    assert vertex_fields["Vertices"]["count"] == 13222
    topology_fields = {field["name"]: field for field in mesh["primary_topology"]["fields"]}
    assert topology_fields["Indices16"]["count"] == 48078


def test_research_native_geometry_when_available():
    if not DEFAULT_RESEARCH_LIB.exists():
        return
    path = SAMPLE_ROOT / "Granny Viewer" / "Gryphon.gr2"
    gr2 = read_gr2(path)
    loaded = load_sections(gr2, ResearchNativeBackend())
    geometry = extract_mesh_geometries(loaded)
    assert len(geometry) == 1
    mesh = geometry[0]
    assert mesh.vertex_count == 13222
    assert mesh.index_count == 48078
    assert mesh.vertex_stride == 32
    assert mesh.positions[0] == (
        -0.3671661615371704,
        4.093114376068115,
        3.745178699493408,
    )
    assert mesh.triangles[0] == (10146, 2639, 10145)


def test_research_native_geometry_uses_32bit_indices_when_available():
    if not DEFAULT_RESEARCH_LIB.exists():
        return
    path = SAMPLE_ROOT / "Granny-3D-SDK-main" / "tutorials" / "media" / "Cube_Texture.GR2"
    gr2 = read_gr2(path)
    loaded = load_sections(gr2, ResearchNativeBackend())
    geometry = extract_mesh_geometries(loaded)
    assert len(geometry) == 1
    mesh = geometry[0]
    assert mesh.vertex_count == 24
    assert mesh.index_count == 36
    assert len(mesh.triangles) == 12
    assert [material.name for material in mesh.materials] == ["Material685"]
    assert mesh.materials[0].texture_file.endswith("BARK5.jpg")
    assert [(group.material_index, group.tri_first, group.tri_count) for group in mesh.triangle_groups] == [
        (0, 0, 12)
    ]


def test_research_native_geometry_reads_vertex_weights_when_available():
    if not DEFAULT_RESEARCH_LIB.exists():
        return
    path = SAMPLE_ROOT / "Granny-3D-SDK-main" / "tutorials" / "media" / "attachment" / "cape.gr2"
    gr2 = read_gr2(path)
    loaded = load_sections(gr2, ResearchNativeBackend())
    geometry = extract_mesh_geometries(loaded)
    assert len(geometry) == 1
    mesh = geometry[0]
    assert [binding.name for binding in mesh.bone_bindings] == ["joint1", "joint2", "joint3", "joint4"]
    assert [(item.bone_index, round(item.weight, 6)) for item in mesh.vertex_weights[0]] == [
        (2, 0.470588),
        (3, 0.466667),
        (1, 0.054902),
        (0, 0.007843),
    ]
    assert round(sum(item.weight for item in mesh.vertex_weights[0]), 6) == 1.0


def test_research_native_skeleton_when_available():
    if not DEFAULT_RESEARCH_LIB.exists():
        return
    path = SAMPLE_ROOT / "Granny-3D-SDK-main" / "tutorials" / "media" / "attachment" / "cape.gr2"
    gr2 = read_gr2(path)
    loaded = load_sections(gr2, ResearchNativeBackend())
    skeletons = extract_skeletons(loaded)
    assert len(skeletons) == 1
    skeleton = skeletons[0]
    assert skeleton.name == "grannyRootBone"
    assert [bone.name for bone in skeleton.bones] == [
        "grannyRootBone",
        "joint1",
        "joint2",
        "joint3",
        "pPlane1",
        "joint4",
    ]
    assert [bone.parent_index for bone in skeleton.bones] == [-1, 0, 1, 2, 0, 3]
    assert round(skeleton.bones[2].transform.position[0], 6) == 4.480867


def test_texture_path_resolution():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        texture = root / "sceneassets" / "images" / "BARK5.jpg"
        texture.parent.mkdir(parents=True)
        texture.write_bytes(b"not a real jpeg")
        gr2_path = root / "models" / "Cube_Texture.GR2"
        gr2_path.parent.mkdir()
        gr2_path.write_bytes(b"")

        source = "C:\\Users\\hara.FHW\\Documents\\3dsMax\\sceneassets\\images\\BARK5.jpg"
        assert texture_basename(source) == "BARK5.jpg"
        assert resolve_texture_path(source, gr2_path, (root,)) == texture


if __name__ == "__main__":
    test_parse_oodle1_gryphon()
    test_oodle1_clean_backend_matches_known_hashes_when_available()
    test_parse_oodle0_granny_rocks()
    test_none_section_decompresses()
    test_oodle0_header_plan()
    test_oodle0_clean_backend_matches_known_hashes_when_available()
    test_oodle0_granny_rocks_load_sections_when_available()
    test_parse_bitknit2_ymir_sample_when_available()
    test_bitknit2_clean_backend_decodes_supported_prefix_when_available()
    test_bitknit_adaptive_model_updates_and_rescales()
    test_bitknit_adaptive_model_take_updates()
    test_bitknit_adaptive_model_accepts_initial_weights()
    test_bitknit_range_decoder_normalizes_first_payload_bytes()
    test_bitknit_range_decoder_take_updates_interval()
    test_bitknit_range_decoder_dll_style_take_helpers()
    test_bitknit_model_sets_have_four_contexts()
    test_bitknit_model_profile_weights_apply_to_all_contexts()
    test_bitknit_zero_biased_profile()
    test_bitknit_decoder_state_takes_context_symbols()
    test_bitknit_decoder_state_decodes_first_uniform_literal_symbol()
    test_bitknit_decoder_state_decodes_zero_biased_control_token()
    test_bitknit_symbol_classification()
    test_bitknit_dll_table_profiles()
    test_bitknit_dll_adaptive_model_rebuilds_on_countdown()
    test_bitknit_dll_word_range_decoder()
    test_bitknit_state7_seed_helper()
    test_bitknit_state7_shared_window_decoder()
    test_bitknit_state7_initial_literal_swap()
    test_bitknit_recent_distance_state()
    test_bitknit_state7_prefix_matches_cached_oracle_when_available()
    test_bitknit2_section0_decompresses_when_available()
    test_bitknit2_native_supported_sections_match_known_hashes_when_available()
    test_bitknit_classic_generated_supported_sections_when_available()
    test_bitknit2_generated_supported_sections_when_available()
    test_bitknit2_compressed_fixups_load_primary_mesh_when_available()
    test_blender_importer_uses_clean_section_loader()
    test_animation_metadata_pixo_run_when_available()
    test_animation_metadata_pixo_dance_when_available()
    test_animation_metadata_metin_legacy_curve_when_available()
    test_bitknit_chunk_fsm_entry_probe_when_available()
    test_bitknit_output_window_literals_and_matches()
    test_missing_file()
    test_research_native_root_summary_when_available()
    test_research_native_mesh_summary_when_available()
    test_research_native_geometry_when_available()
    test_research_native_geometry_uses_32bit_indices_when_available()
    test_research_native_geometry_reads_vertex_weights_when_available()
    test_research_native_skeleton_when_available()
    test_texture_path_resolution()
