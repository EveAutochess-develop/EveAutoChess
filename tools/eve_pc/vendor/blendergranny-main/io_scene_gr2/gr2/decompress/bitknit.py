"""Clean BitKnit container reader.

Only lightweight structure checks live here for now. The entropy/LZ decoder is
still pending, but this gives us safe sample inspection and stable tests.
"""

from __future__ import annotations

import struct
from bisect import bisect_right
from dataclasses import dataclass

from io_scene_gr2.gr2.constants import COMPRESSION_BITKNIT, COMPRESSION_BITKNIT2
from io_scene_gr2.gr2.decompress.base import DecompressionUnsupported
from io_scene_gr2.gr2.file import GR2Section

BITKNIT_HEADER_SIZE = 48
BITKNIT_BLOCK_COUNT = 4
BITKNIT2_MARKER = 0x75B1
BITKNIT_WORD_MASK = 0xFFFFFFFF
BITKNIT_MODEL_UPDATE = 31
BITKNIT_INITIAL_WEIGHT = 1
BITKNIT_LITERAL_SYMBOLS = 0x205
BITKNIT_MATCH_SYMBOLS = 0x45
BITKNIT_DLL_LITERAL_TABLE_SYMBOLS = 0x12C
BITKNIT_DLL_SHORT_DISTANCE_SYMBOLS = 0x15
BITKNIT_DLL_LONG_DISTANCE_SYMBOLS = 0x28
BITKNIT_LITERAL_LIMIT = 0x100
BITKNIT_SHORT_MATCH_BASE = 0x100
BITKNIT_EXTRA_MATCH_BASE = 0x120
BITKNIT_CONTEXT_STRIDE = 4
BITKNIT_RECENT_DISTANCE_COUNT = 8
BITKNIT_DISTANCE_LOW_BITS = 5
BITKNIT_CHUNK_SIZE = 16
BITKNIT_RANGE_INITIAL = 0x80
BITKNIT_RANGE_NORMALIZE_LIMIT = 0x800000
BITKNIT_SECTION6_RECORD_SIZE = 32
BITKNIT_SECTION6_INITIAL_FILL_RECORDS = 2
BITKNIT_INITIAL_RECENT_DISTANCE = 1
BITKNIT_INITIAL_RECENT_SELECTOR = 0xFAC688
BITKNIT_FSM_INITIAL = 1
BITKNIT_FSM_CHECK_BLOCK = 2
BITKNIT_FSM_DONE = 3
BITKNIT_FSM_COPY_EVEN = 4
BITKNIT_FSM_COPY_ODD = 5
BITKNIT_FSM_COMPRESSED = 7
BITKNIT_FSM_COMPRESSED_ALT = 8
BITKNIT2_STATE7_VERIFIED_TAGS = frozenset((0x1, 0x2, 0x3, 0x12, 0x14, 0x50, 0x14E, 0x518, 0x7D18))
BITKNIT2_BLOCK_OUTPUT_SIZE = 0x10000


@dataclass(frozen=True)
class BitKnitHeader:
    words: tuple[int, ...]

    @property
    def marker(self) -> int:
        return self.words[0] & 0xFFFF if self.words else 0

    @property
    def header_tag(self) -> int:
        return self.words[0] >> 16 if self.words else 0

    @property
    def looks_like_bitknit2(self) -> bool:
        return self.marker == BITKNIT2_MARKER

    def to_dict(self) -> dict:
        return {
            "marker": self.marker,
            "header_tag": self.header_tag,
            "looks_like_bitknit2": self.looks_like_bitknit2,
            "words": list(self.words),
        }


@dataclass(frozen=True)
class BitKnitPlan:
    section_index: int
    compression_name: str
    compressed_size: int
    expanded_size: int
    first_16bit: int
    first_8bit: int
    header: BitKnitHeader | None
    payload_offset: int

    @property
    def is_empty(self) -> bool:
        return self.expanded_size == 0

    def to_dict(self) -> dict:
        return {
            "section_index": self.section_index,
            "compression": self.compression_name,
            "compressed_size": self.compressed_size,
            "expanded_size": self.expanded_size,
            "first_16bit": self.first_16bit,
            "first_8bit": self.first_8bit,
            "payload_offset": self.payload_offset,
            "header": self.header.to_dict() if self.header else None,
        }


@dataclass
class BitKnitBitReader:
    data: bytes
    byte_offset: int = BITKNIT_HEADER_SIZE
    bit_buffer: int = 0
    bit_count: int = 0

    @property
    def remaining_bytes(self) -> int:
        return max(0, len(self.data) - self.byte_offset)

    def read_bits(self, count: int) -> int:
        if count < 0:
            raise ValueError("bit count must be non-negative")
        if count == 0:
            return 0
        while self.bit_count < count:
            if self.byte_offset >= len(self.data):
                raise EOFError("bitknit bitstream exhausted")
            self.bit_buffer |= self.data[self.byte_offset] << self.bit_count
            self.byte_offset += 1
            self.bit_count += 8
        mask = (1 << count) - 1
        value = self.bit_buffer & mask
        self.bit_buffer >>= count
        self.bit_count -= count
        return value


@dataclass
class BitKnitHeaderBitReader:
    """LSB-first reader over the 48-byte BitKnit header/control seed area."""

    data: bytes
    bit_offset: int = 0
    byte_limit: int = BITKNIT_HEADER_SIZE

    @property
    def remaining_bits(self) -> int:
        return max(0, self.byte_limit * 8 - self.bit_offset)

    def read_bits(self, count: int) -> int:
        value = peek_bitknit_header_bits(self.data, self.bit_offset, count, self.byte_limit)
        self.bit_offset += count
        return value

    def read_signed_bits(self, count: int) -> int:
        value = self.read_bits(count)
        return sign_extend(value, count)


@dataclass
class BitKnitWordStream:
    data: bytes
    byte_offset: int = BITKNIT_HEADER_SIZE

    @property
    def remaining_bytes(self) -> int:
        return max(0, len(self.data) - self.byte_offset)

    def read_u32le(self) -> int:
        if self.byte_offset + 4 > len(self.data):
            raise EOFError("bitknit word stream exhausted")
        value = struct.unpack_from("<I", self.data, self.byte_offset)[0]
        self.byte_offset += 4
        return value & BITKNIT_WORD_MASK


@dataclass(frozen=True)
class BitKnitPayloadChunk:
    offset: int
    data: bytes
    words: tuple[int, ...]

    @property
    def is_full(self) -> bool:
        return len(self.data) == BITKNIT_CHUNK_SIZE


@dataclass(frozen=True)
class BitKnitChunkFsmCheckpoint:
    state: int
    input_offset: int
    marker: int
    block_word: int | None

    @property
    def uses_compressed_handler(self) -> bool:
        return self.state in (BITKNIT_FSM_COMPRESSED, BITKNIT_FSM_COMPRESSED_ALT)

    def to_dict(self) -> dict:
        return {
            "state": self.state,
            "input_offset": self.input_offset,
            "marker": self.marker,
            "block_word": self.block_word,
            "uses_compressed_handler": self.uses_compressed_handler,
        }


@dataclass
class BitKnitChunkStream:
    data: bytes
    byte_offset: int = BITKNIT_HEADER_SIZE
    chunk_size: int = BITKNIT_CHUNK_SIZE

    @property
    def remaining_bytes(self) -> int:
        return max(0, len(self.data) - self.byte_offset)

    def read_chunk(self) -> BitKnitPayloadChunk:
        if self.byte_offset >= len(self.data):
            raise EOFError("bitknit chunk stream exhausted")
        offset = self.byte_offset
        end = min(len(self.data), offset + self.chunk_size)
        chunk = self.data[offset:end]
        self.byte_offset = end
        padded = chunk + b"\x00" * ((4 - len(chunk) % 4) % 4)
        words = struct.unpack("<" + "I" * (len(padded) // 4), padded) if padded else ()
        return BitKnitPayloadChunk(offset=offset, data=chunk, words=words)


@dataclass
class BitKnitRangeDecoder:
    """Range-decoder state matching observed BitKnit byte/refill mechanics."""

    data: bytes
    byte_offset: int
    code: int
    span: int = BITKNIT_RANGE_INITIAL
    carry_bit: int = 0
    scale: int = 0

    @classmethod
    def from_payload(cls, data: bytes, payload_offset: int) -> "BitKnitRangeDecoder":
        if payload_offset >= len(data):
            raise EOFError("bitknit range decoder needs at least one payload byte")
        first = data[payload_offset]
        return cls(
            data=data,
            byte_offset=payload_offset + 1,
            code=first >> 1,
            carry_bit=first & 1,
        )

    @property
    def remaining_bytes(self) -> int:
        return max(0, len(self.data) - self.byte_offset)

    def normalize(self) -> None:
        while self.span <= BITKNIT_RANGE_NORMALIZE_LIMIT:
            if self.byte_offset >= len(self.data):
                raise EOFError("bitknit range decoder exhausted")
            byte = self.data[self.byte_offset]
            self.byte_offset += 1
            self.code = (((self.code * 2) + self.carry_bit) << 7) | (byte >> 1)
            self.span <<= 8
            self.carry_bit = byte & 1

    def peek(self, total: int) -> int:
        if total <= 0:
            raise ValueError("range total must be positive")
        self.normalize()
        scale = self.span // total
        if scale <= 0:
            raise ValueError("range total exceeds decoder span")
        self.scale = scale
        value = self.code // scale
        return min(value, total - 1)

    def peek_shifted(self, shift: int, cap: int) -> int:
        if shift < 0:
            raise ValueError("range shift must be non-negative")
        if cap <= 0:
            raise ValueError("range cap must be positive")
        self.normalize()
        scale = self.span >> shift
        if scale <= 0:
            raise ValueError("range shift exceeds decoder span")
        self.scale = scale
        value = self.code // scale
        return min(value, cap - 1)

    def take(self, symbol_range: BitKnitSymbolRange) -> None:
        self.normalize()
        scale = self.span // symbol_range.total
        if scale <= 0:
            raise ValueError("range total exceeds decoder span")
        self.scale = scale
        self.code -= symbol_range.low * scale
        if symbol_range.high < symbol_range.total:
            self.span = (symbol_range.high - symbol_range.low) * scale
        else:
            self.span -= symbol_range.low * scale

    def take_uniform(self, total: int) -> int:
        value = self.peek(total)
        low = value
        high = value + 1
        self.code -= low * self.scale
        if high < total:
            self.span = self.scale
        else:
            self.span -= low * self.scale
        return value

    def take_shifted(self, shift: int, cap: int) -> int:
        value = self.peek_shifted(shift, cap)
        low = value
        high = value + 1
        self.code -= low * self.scale
        if high < cap:
            self.span = self.scale
        else:
            self.span -= low * self.scale
        return value

    def take_scaled_range(self, low: int, width: int, total: int) -> None:
        if low < 0 or width <= 0 or total <= 0:
            raise ValueError("invalid scaled range")
        if low + width > total:
            raise ValueError("scaled range exceeds total")
        self.normalize()
        scale = self.span // total
        if scale <= 0:
            raise ValueError("range total exceeds decoder span")
        self.scale = scale
        self.code -= low * scale
        if low + width < total:
            self.span = width * scale
        else:
            self.span -= low * scale

    def take_from_model(self, model: "BitKnitAdaptiveModel") -> BitKnitSymbolRange:
        value = self.peek(model.total)
        decoded = model.lookup(value)
        self.take(decoded)
        model.update(decoded.symbol)
        return decoded


@dataclass(frozen=True)
class BitKnitSymbolRange:
    symbol: int
    low: int
    high: int
    total: int


def lookup_dll_table_symbol(
    profile: "BitKnitDllTableProfile",
    value: int,
) -> BitKnitSymbolRange:
    if value < 0:
        raise ValueError("DLL table value must be non-negative")
    cumulative = profile.cumulative
    if value >= cumulative[-1]:
        raise ValueError(f"DLL table value out of range: {value}")
    symbol = bisect_right(cumulative, value) - 1
    return BitKnitSymbolRange(
        symbol=symbol,
        low=cumulative[symbol],
        high=cumulative[symbol + 1],
        total=cumulative[-1],
    )


@dataclass
class BitKnitWordRangeDecoder:
    """15-bit/u16 range state used by the `0x10068f10` BitKnit2 loop."""

    data: bytes
    word_offset: int
    window: int

    @property
    def value15(self) -> int:
        return self.window & 0x7FFF

    @property
    def remaining_bytes(self) -> int:
        return max(0, len(self.data) - self.word_offset)

    def read_u16le(self) -> int:
        if self.word_offset + 2 > len(self.data):
            raise EOFError("bitknit word-range decoder exhausted")
        value = struct.unpack_from("<H", self.data, self.word_offset)[0]
        self.word_offset += 2
        return value

    def take(self, symbol_range: BitKnitSymbolRange) -> None:
        width = symbol_range.high - symbol_range.low
        if width <= 0:
            raise ValueError("DLL table symbol range must be non-empty")
        next_window = (
            self.value15
            + ((self.window >> 15) * width)
            - symbol_range.low
        )
        if next_window < 0x10000:
            next_window = ((next_window & 0xFFFF) << 16) | self.read_u16le()
        self.window = next_window & BITKNIT_WORD_MASK

    def take_from_dll_profile(self, profile: "BitKnitDllTableProfile") -> BitKnitSymbolRange:
        decoded = lookup_dll_table_symbol(profile, self.value15)
        self.take(decoded)
        return decoded

    def take_from_dll_model(self, model: "BitKnitDllAdaptiveModel") -> BitKnitSymbolRange:
        decoded = model.lookup(self.value15)
        self.take(decoded)
        model.update(decoded.symbol)
        return decoded


@dataclass(frozen=True)
class BitKnitState7Seed:
    input_offset: int
    initial_word: int
    primary_window: int
    range_window: int
    extra_window: int
    extra_bits: int

    def to_dict(self) -> dict:
        return {
            "input_offset": self.input_offset,
            "initial_word": f"0x{self.initial_word:08x}",
            "primary_window": f"0x{self.primary_window:08x}",
            "range_window": f"0x{self.range_window:08x}",
            "extra_window": f"0x{self.extra_window:08x}",
            "extra_bits": self.extra_bits,
        }


@dataclass(frozen=True)
class BitKnitState7PrefixResult:
    output: bytes
    trace: tuple[dict, ...]
    stopped: str | None
    checkpoint: BitKnitChunkFsmCheckpoint
    seed: BitKnitState7Seed


@dataclass(frozen=True)
class BitKnitState7StreamResult:
    output: bytes
    trace: tuple[dict, ...]
    stopped: str | None
    checkpoint: BitKnitChunkFsmCheckpoint
    first_seed: BitKnitState7Seed
    block_count: int


@dataclass
class BitKnitState7WindowDecoder:
    """Shared word pointer for state-7 range and extra-bit windows."""

    data: bytes
    word_offset: int
    range_window: int
    extra_window: int

    @classmethod
    def from_seed(cls, data: bytes, seed: BitKnitState7Seed) -> "BitKnitState7WindowDecoder":
        return cls(
            data=data,
            word_offset=seed.input_offset,
            range_window=seed.range_window,
            extra_window=seed.extra_window,
        )

    @property
    def value15(self) -> int:
        return self.range_window & 0x7FFF

    def read_u16le(self) -> int:
        value, self.word_offset = _read_bitknit_u16le(self.data, self.word_offset)
        return value

    def take_range(self, symbol_range: BitKnitSymbolRange) -> None:
        width = symbol_range.high - symbol_range.low
        if width <= 0:
            raise ValueError("DLL table symbol range must be non-empty")
        next_window = (
            self.value15
            + ((self.range_window >> 15) * width)
            - symbol_range.low
        )
        if next_window < 0x10000:
            next_window = ((next_window & 0xFFFF) << 16) | self.read_u16le()
        self.range_window = next_window & BITKNIT_WORD_MASK

    def take_from_dll_profile(self, profile: "BitKnitDllTableProfile") -> BitKnitSymbolRange:
        decoded = lookup_dll_table_symbol(profile, self.value15)
        self.take_range(decoded)
        return decoded

    def take_from_dll_model(self, model: "BitKnitDllAdaptiveModel") -> BitKnitSymbolRange:
        decoded = model.lookup(self.value15)
        self.take_range(decoded)
        model.update(decoded.symbol)
        return decoded

    def take_swapped_from_dll_profile(
        self,
        profile: "BitKnitDllTableProfile",
    ) -> BitKnitSymbolRange:
        old_other = self.extra_window
        decoded = self.take_from_dll_profile(profile)
        updated_current = self.range_window
        self.range_window = old_other
        self.extra_window = updated_current
        return decoded

    def take_swapped_from_dll_model(
        self,
        model: "BitKnitDllAdaptiveModel",
    ) -> BitKnitSymbolRange:
        old_other = self.extra_window
        decoded = self.take_from_dll_model(model)
        updated_current = self.range_window
        self.range_window = old_other
        self.extra_window = updated_current
        return decoded

    def read_extra_bits(self, count: int) -> int:
        if count < 0:
            raise ValueError("extra bit count must be non-negative")
        if count == 0:
            return 0
        before = self.extra_window
        shifted = before >> count
        if shifted < 0x10000:
            shifted = ((shifted & 0xFFFF) << 16) | self.read_u16le()
        self.extra_window = shifted & BITKNIT_WORD_MASK
        return before & ((1 << count) - 1)

    def read_swapped_extra_bits(self, count: int) -> int:
        if count < 0:
            raise ValueError("extra bit count must be non-negative")
        if count == 0:
            return 0
        before = self.range_window
        shifted = before >> count
        if shifted < 0x10000:
            shifted = ((shifted & 0xFFFF) << 16) | self.read_u16le()
        self.range_window, self.extra_window = self.extra_window, shifted & BITKNIT_WORD_MASK
        return before & ((1 << count) - 1)


@dataclass
class BitKnitRecentDistanceState:
    distances: list[int]
    selector: int = BITKNIT_INITIAL_RECENT_SELECTOR

    @classmethod
    def initial(cls) -> "BitKnitRecentDistanceState":
        return cls([BITKNIT_INITIAL_RECENT_DISTANCE] * BITKNIT_RECENT_DISTANCE_COUNT)

    def take_recent(self, symbol: int) -> tuple[int, int]:
        if symbol < 0 or symbol >= BITKNIT_RECENT_DISTANCE_COUNT:
            raise ValueError(f"recent distance symbol out of range: {symbol}")
        shift = symbol * 3
        slot = (self.selector >> shift) & 7
        distance = self.distances[slot]
        clear_mask = (0xFFFFFFF8 << shift) & BITKNIT_WORD_MASK
        low_mask = (~clear_mask) & BITKNIT_WORD_MASK
        promoted = (slot + ((self.selector << 3) & BITKNIT_WORD_MASK)) & low_mask
        preserved = self.selector & clear_mask
        self.selector = (promoted | preserved) & BITKNIT_WORD_MASK
        return distance, slot

    def insert_direct(self, distance: int) -> tuple[int, int]:
        if distance <= 0:
            raise ValueError("direct distance must be positive")
        source_slot = (self.selector >> 0x12) & 7
        target_slot = (self.selector >> 0x15) & 7
        self.distances[target_slot] = self.distances[source_slot]
        self.distances[source_slot] = distance
        return source_slot, target_slot


class BitKnitState7Core:
    def __init__(
        self,
        compressed: bytes,
        expanded_size: int,
        *,
        with_trace: bool = False,
    ) -> None:
        self.compressed = compressed
        self.literal_models = [
            BitKnitDllAdaptiveModel(make_dll_literal_table_profile()) for _ in range(4)
        ]
        self.long_distance_models = [
            BitKnitDllAdaptiveModel(make_dll_long_distance_table_profile()) for _ in range(4)
        ]
        self.short_distance_model = BitKnitDllAdaptiveModel(make_dll_short_distance_table_profile())
        self.output = BitKnitOutputWindow(expanded_size)
        self.recent = BitKnitRecentDistanceState.initial()
        self.last_distance = BITKNIT_INITIAL_RECENT_DISTANCE
        self.trace: list[dict] = []
        self.with_trace = with_trace
        self.step = 0

    def start_block(
        self,
        input_offset: int,
        *,
        emit_initial_literal: bool,
    ) -> tuple[BitKnitState7Seed, BitKnitState7WindowDecoder]:
        seed = seed_bitknit_state7_word_ranges(self.compressed, input_offset)
        if emit_initial_literal:
            initial_literal, decoder = make_state7_decoder_after_initial_literal(self.compressed, seed)
            if self.output.offset < self.output.expected_size:
                self.output.append_literal_delta(initial_literal)
                if self.with_trace:
                    self.trace.append(
                        {
                            "step": self.step,
                            "offset": self.output.offset - 1,
                            "context": (self.output.offset - 1) & 3,
                            "symbol": initial_literal,
                            "kind": "initial-literal",
                            "range_window": f"0x{decoder.range_window:08x}",
                            "extra_window": f"0x{decoder.extra_window:08x}",
                            "word_offset": decoder.word_offset,
                            "output_byte": self.output.data[-1],
                        }
                    )
                self.step += 1
        else:
            decoder = BitKnitState7WindowDecoder.from_seed(self.compressed, seed)
        return seed, decoder

    def decode_block(
        self,
        decoder: BitKnitState7WindowDecoder,
        target_size: int,
        *,
        max_steps: int | None = None,
        stop_at_word_sentinel: bool = False,
    ) -> str | None:
        while self.output.offset < target_size:
            if max_steps is not None and self.step >= max_steps:
                return "step limit reached"

            offset = self.output.offset
            context = offset & 3
            symbol_range = decoder.take_swapped_from_dll_model(self.literal_models[context])
            kind = classify_bitknit_symbol(symbol_range.symbol)
            row = {
                "step": self.step,
                "offset": offset,
                "context": context,
                "symbol": symbol_range.symbol,
                "kind": kind.name,
                "range": [symbol_range.low, symbol_range.high, symbol_range.total],
                "range_window": f"0x{decoder.range_window:08x}",
                "extra_window": f"0x{decoder.extra_window:08x}",
                "word_offset": decoder.word_offset,
            }
            if kind.name == "literal":
                self.output.append_literal_from_distance(symbol_range.symbol, self.last_distance)
                row["output_byte"] = self.output.data[-1]
            else:
                extra_value = 0
                if kind.needs_extra_bits:
                    extra_bits = symbol_range.symbol - 0x11F
                    extra_value = decoder.read_swapped_extra_bits(extra_bits)
                    row["length_extra_value"] = extra_value
                length = describe_length_symbol(symbol_range.symbol, extra_value)
                if self.output.offset + length.length > self.output.expected_size:
                    row["length"] = length.to_dict()
                    row["stop"] = "match exceeds output"
                    if self.with_trace:
                        self.trace.append(row)
                    return "match exceeds output"
                long_symbol = decoder.take_swapped_from_dll_model(
                    self.long_distance_models[offset & 3]
                ).symbol
                distance = describe_distance_symbol(long_symbol)
                row["length"] = length.to_dict()
                row["distance_symbol"] = distance.to_dict()
                if distance.is_recent:
                    match_distance, slot = self.recent.take_recent(long_symbol)
                    row["recent_slot"] = slot
                    row["resolved_distance"] = match_distance
                    self.output.copy_match(match_distance, length.length)
                    self.last_distance = match_distance
                else:
                    short_symbol = decoder.take_from_dll_model(self.short_distance_model).symbol
                    direct_extra = decoder.read_extra_bits(short_symbol)
                    direct = describe_direct_distance_symbols(
                        long_symbol,
                        short_symbol,
                        direct_extra,
                    )
                    row["direct_distance"] = direct.to_dict()
                    if direct.distance > self.output.offset:
                        row["stop"] = "direct distance exceeds output"
                        if self.with_trace:
                            self.trace.append(row)
                        return "direct distance exceeds output"
                    source_slot, target_slot = self.recent.insert_direct(direct.distance)
                    row["direct_recent_source_slot"] = source_slot
                    row["direct_recent_target_slot"] = target_slot
                    self.output.copy_match(direct.distance, length.length)
                    self.last_distance = direct.distance
                row["output_offset_after"] = self.output.offset
                row["last_distance"] = self.last_distance
            if self.with_trace:
                self.trace.append(row)
            self.step += 1
            if (
                stop_at_word_sentinel
                and self.output.offset < target_size
                and decoder.range_window == 0x10000
                and decoder.extra_window == 0x10000
            ):
                return "state7 block sentinel"
        return None


def make_state7_decoder_after_initial_literal(
    data: bytes,
    seed: BitKnitState7Seed,
) -> tuple[int, BitKnitState7WindowDecoder]:
    """Model the one-byte pre-loop literal at `0x100690ac..0x10069104`."""

    literal = seed.range_window & 0xFF
    offset = seed.input_offset
    extra_window = seed.range_window >> 8
    if extra_window < 0x10000:
        refill, offset = _read_bitknit_u16le(data, offset)
        extra_window = ((extra_window & 0xFFFF) << 16) | refill
    return literal, BitKnitState7WindowDecoder(
        data=data,
        word_offset=offset,
        range_window=seed.extra_window,
        extra_window=extra_window & BITKNIT_WORD_MASK,
    )


def decode_bitknit_state7_prefix(
    compressed: bytes,
    expanded_size: int,
    *,
    max_output_size: int | None = None,
    max_steps: int | None = None,
    with_trace: bool = False,
) -> BitKnitState7PrefixResult:
    if expanded_size < 0:
        raise ValueError("expanded size must be non-negative")
    target_size = expanded_size if max_output_size is None else min(max_output_size, expanded_size)
    if target_size < 0:
        raise ValueError("max output size must be non-negative")

    checkpoint = probe_bitknit_chunk_fsm_entry(compressed)
    if not checkpoint.uses_compressed_handler:
        raise ValueError(f"bitknit section does not enter state7: {checkpoint.to_dict()}")
    core = BitKnitState7Core(compressed, expanded_size, with_trace=with_trace)
    seed, decoder = core.start_block(checkpoint.input_offset, emit_initial_literal=True)
    stopped = core.decode_block(decoder, target_size, max_steps=max_steps)

    return BitKnitState7PrefixResult(
        output=bytes(core.output.data[:target_size]),
        trace=tuple(core.trace),
        stopped=stopped,
        checkpoint=checkpoint,
        seed=seed,
    )


def decode_bitknit_state7_stream(
    compressed: bytes,
    expanded_size: int,
    *,
    max_output_size: int | None = None,
    max_steps: int | None = None,
    with_trace: bool = False,
    emit_initial_literal_each_block: bool = False,
) -> BitKnitState7StreamResult:
    if expanded_size < 0:
        raise ValueError("expanded size must be non-negative")
    target_size = expanded_size if max_output_size is None else min(max_output_size, expanded_size)
    if target_size < 0:
        raise ValueError("max output size must be non-negative")

    checkpoint = probe_bitknit_chunk_fsm_entry(compressed)
    if not checkpoint.uses_compressed_handler:
        raise ValueError(f"bitknit section does not enter state7: {checkpoint.to_dict()}")

    core = BitKnitState7Core(compressed, expanded_size, with_trace=with_trace)
    input_offset = checkpoint.input_offset
    block_count = 0
    first_seed: BitKnitState7Seed | None = None
    stopped: str | None = None

    while core.output.offset < target_size:
        block_end = min(
            ((core.output.offset // BITKNIT2_BLOCK_OUTPUT_SIZE) + 1)
            * BITKNIT2_BLOCK_OUTPUT_SIZE,
            target_size,
        )
        seed, decoder = core.start_block(
            input_offset,
            emit_initial_literal=block_count == 0 or emit_initial_literal_each_block,
        )
        if first_seed is None:
            first_seed = seed
        block_count += 1
        stopped = core.decode_block(decoder, block_end, max_steps=max_steps)
        input_offset = decoder.word_offset
        if stopped is not None:
            break
        if core.output.offset >= target_size:
            break
        if decoder.range_window != 0x10000 or decoder.extra_window != 0x10000:
            stopped = (
                "state7 block ended without word-window sentinels "
                f"(range=0x{decoder.range_window:08x}, extra=0x{decoder.extra_window:08x})"
            )
            break
        if input_offset + 2 > len(compressed):
            stopped = "missing next block word"
            break
        block_word = struct.unpack_from("<H", compressed, input_offset)[0]
        if block_word == 0:
            stopped = "raw copy block not implemented"
            break

    if first_seed is None:
        first_seed = BitKnitState7Seed(
            input_offset=checkpoint.input_offset,
            initial_word=0,
            primary_window=0,
            range_window=0,
            extra_window=0,
            extra_bits=0,
        )
    return BitKnitState7StreamResult(
        output=bytes(core.output.data[:target_size]),
        trace=tuple(core.trace),
        stopped=stopped,
        checkpoint=checkpoint,
        first_seed=first_seed,
        block_count=block_count,
    )


def _read_bitknit_u16le(data: bytes, offset: int) -> tuple[int, int]:
    if offset + 2 > len(data):
        raise EOFError("bitknit u16 stream exhausted")
    return struct.unpack_from("<H", data, offset)[0], offset + 2


def seed_bitknit_state7_word_ranges(data: bytes, input_offset: int) -> BitKnitState7Seed:
    """Clean port of the `0x1006ba30` state-7 word-window seeding helper."""

    if input_offset < 0:
        raise ValueError("input offset must be non-negative")
    high, input_offset = _read_bitknit_u16le(data, input_offset)
    low, input_offset = _read_bitknit_u16le(data, input_offset)
    initial_word = ((high << 16) | low) & BITKNIT_WORD_MASK

    primary = initial_word >> 4
    if primary < 0x10000:
        refill, input_offset = _read_bitknit_u16le(data, input_offset)
        primary = ((primary << 16) | refill) & BITKNIT_WORD_MASK

    extra_bits = (initial_word & 0xF) + 0x10
    range_window = primary >> (extra_bits & 0xF)
    if range_window < 0x10000:
        refill, input_offset = _read_bitknit_u16le(data, input_offset)
        range_window = ((range_window << 16) | refill) & BITKNIT_WORD_MASK

    extra_source = primary
    if extra_bits >= 0x10:
        refill, input_offset = _read_bitknit_u16le(data, input_offset)
        extra_source = ((primary << 16) | refill) & BITKNIT_WORD_MASK

    mask = (1 << extra_bits) - 1
    extra_window = ((extra_source & mask) | (1 << extra_bits)) & BITKNIT_WORD_MASK
    return BitKnitState7Seed(
        input_offset=input_offset,
        initial_word=initial_word,
        primary_window=primary,
        range_window=range_window,
        extra_window=extra_window,
        extra_bits=extra_bits,
    )


@dataclass(frozen=True)
class BitKnitSymbolKind:
    name: str
    needs_extra_bits: bool = False


@dataclass(frozen=True)
class BitKnitMatchDescriptor:
    symbol: int
    index: int
    needs_extra_bits: bool

    def to_dict(self) -> dict:
        return {
            "symbol": self.symbol,
            "index": self.index,
            "needs_extra_bits": self.needs_extra_bits,
        }


@dataclass(frozen=True)
class BitKnitControlDescriptor:
    symbol: int
    index: int
    needs_extra_bits: bool
    low5: int
    group: int

    def to_dict(self) -> dict:
        return {
            "symbol": self.symbol,
            "index": self.index,
            "needs_extra_bits": self.needs_extra_bits,
            "low5": self.low5,
            "group": self.group,
        }


@dataclass(frozen=True)
class BitKnitDistanceDescriptor:
    symbol: int
    is_recent: bool
    recent_index: int | None
    direct_index: int | None
    low5: int | None
    group: int
    needs_extra_bits: bool

    def to_dict(self) -> dict:
        return {
            "symbol": self.symbol,
            "is_recent": self.is_recent,
            "recent_index": self.recent_index,
            "direct_index": self.direct_index,
            "low5": self.low5,
            "group": self.group,
            "needs_extra_bits": self.needs_extra_bits,
        }


@dataclass(frozen=True)
class BitKnitDirectDistanceDescriptor:
    long_symbol: int
    short_symbol: int
    extra_bits: int
    extra_value: int
    distance: int

    @property
    def needs_extra_bits(self) -> bool:
        return self.extra_bits > 0

    def to_dict(self) -> dict:
        return {
            "long_symbol": self.long_symbol,
            "short_symbol": self.short_symbol,
            "extra_bits": self.extra_bits,
            "extra_value": self.extra_value,
            "needs_extra_bits": self.needs_extra_bits,
            "distance": self.distance,
        }


@dataclass(frozen=True)
class BitKnitLengthDescriptor:
    symbol: int
    length: int
    extra_bits: int
    extra_value: int

    @property
    def needs_extra_bits(self) -> bool:
        return self.extra_bits > 0

    def to_dict(self) -> dict:
        return {
            "symbol": self.symbol,
            "length": self.length,
            "extra_bits": self.extra_bits,
            "extra_value": self.extra_value,
            "needs_extra_bits": self.needs_extra_bits,
        }


@dataclass(frozen=True)
class BitKnitExtraBitsRecord:
    low: int
    tag: int

    @property
    def bit_count(self) -> int:
        if self.tag & 0xC000 == 0xC000:
            return 16
        return self.tag & 0x3FFF

    @property
    def is_terminal16(self) -> bool:
        return (self.tag & 0xC000) == 0xC000


@dataclass(frozen=True)
class BitKnitDllTableProfile:
    cumulative: tuple[int, ...]
    update_weight: int
    rebuild_interval: int

    @property
    def weights(self) -> tuple[int, ...]:
        return tuple(
            self.cumulative[index + 1] - self.cumulative[index]
            for index in range(len(self.cumulative) - 1)
        )


class BitKnitDllAdaptiveModel:
    """DLL-style delayed adaptive cumulative table.

    The hot loop only increments per-symbol weights and decrements a countdown.
    When the countdown reaches zero, the DLL applies a larger final increment,
    rebuilds cumulative entries halfway toward the running weight sums, resets
    weights to 1, and resets the countdown.
    """

    def __init__(self, profile: BitKnitDllTableProfile) -> None:
        self.cumulative = list(profile.cumulative)
        self.weights = [1] * (len(self.cumulative) - 1)
        self.update_weight = profile.update_weight
        self.rebuild_interval = profile.rebuild_interval
        self.countdown = profile.rebuild_interval

    @property
    def total(self) -> int:
        return self.cumulative[-1]

    def lookup(self, value: int) -> BitKnitSymbolRange:
        return lookup_dll_table_symbol(
            BitKnitDllTableProfile(tuple(self.cumulative), self.update_weight, self.rebuild_interval),
            value,
        )

    def update(self, symbol: int) -> None:
        if symbol < 0 or symbol >= len(self.weights):
            raise ValueError(f"symbol out of range: {symbol}")
        self.weights[symbol] += BITKNIT_MODEL_UPDATE
        self.countdown -= 1
        if self.countdown <= 0:
            self.weights[symbol] += self.update_weight
            self._rebuild()

    def _rebuild(self) -> None:
        running = 0
        for index, weight in enumerate(self.weights):
            running += weight
            old = self.cumulative[index + 1]
            self.cumulative[index + 1] = (old + running) >> 1
            self.weights[index] = 1
        self.countdown = self.rebuild_interval


@dataclass(frozen=True)
class BitKnitDecodedToken:
    output_offset: int
    context: int
    symbol_range: BitKnitSymbolRange
    kind: BitKnitSymbolKind

    @property
    def symbol(self) -> int:
        return self.symbol_range.symbol

    def to_dict(self) -> dict:
        result = {
            "offset": self.output_offset,
            "context": self.context,
            "kind": self.kind.name,
            "needs_extra_bits": self.kind.needs_extra_bits,
            "symbol": self.symbol,
            "range": [
                self.symbol_range.low,
                self.symbol_range.high,
                self.symbol_range.total,
            ],
        }
        match_descriptor = describe_match_symbol(self.symbol)
        if match_descriptor:
            result["match"] = match_descriptor.to_dict()
        control_descriptor = describe_control_symbol(self.symbol)
        if control_descriptor:
            result["control"] = control_descriptor.to_dict()
            result["distance"] = describe_distance_symbol(control_descriptor.index).to_dict()
        return result


@dataclass(frozen=True)
class BitKnitSection6FillCandidate:
    bit_offset: int
    seed: int
    fill: int
    prefix_size: int

    def to_dict(self) -> dict:
        return {
            "bit_offset": self.bit_offset,
            "seed": self.seed,
            "fill": self.fill,
            "prefix_size": self.prefix_size,
        }


BITKNIT_LITERAL_KIND = BitKnitSymbolKind("literal")
BITKNIT_SHORT_MATCH_KIND = BitKnitSymbolKind("match")
BITKNIT_EXTRA_MATCH_KIND = BitKnitSymbolKind("match", needs_extra_bits=True)


def classify_bitknit_symbol(symbol: int) -> BitKnitSymbolKind:
    if symbol < 0:
        raise ValueError(f"symbol out of range: {symbol}")
    if symbol < BITKNIT_LITERAL_LIMIT:
        return BITKNIT_LITERAL_KIND
    if symbol < BITKNIT_EXTRA_MATCH_BASE:
        return BITKNIT_SHORT_MATCH_KIND
    return BITKNIT_EXTRA_MATCH_KIND


def describe_match_symbol(symbol: int) -> BitKnitMatchDescriptor | None:
    kind = classify_bitknit_symbol(symbol)
    if kind.name != "match":
        return None
    if symbol < BITKNIT_EXTRA_MATCH_BASE:
        return BitKnitMatchDescriptor(
            symbol=symbol,
            index=symbol - BITKNIT_SHORT_MATCH_BASE,
            needs_extra_bits=False,
        )
    return BitKnitMatchDescriptor(
        symbol=symbol,
        index=symbol - BITKNIT_EXTRA_MATCH_BASE,
        needs_extra_bits=True,
    )


def describe_control_symbol(symbol: int) -> BitKnitControlDescriptor | None:
    kind = classify_bitknit_symbol(symbol)
    if kind.name != "match":
        return None
    if symbol < BITKNIT_EXTRA_MATCH_BASE:
        index = symbol - BITKNIT_SHORT_MATCH_BASE
        return BitKnitControlDescriptor(
            symbol=symbol,
            index=index,
            needs_extra_bits=False,
            low5=index & 0x1F,
            group=0,
        )
    index = symbol - BITKNIT_EXTRA_MATCH_BASE
    return BitKnitControlDescriptor(
        symbol=symbol,
        index=index,
        needs_extra_bits=True,
        low5=index & 0x1F,
        group=index >> 5,
    )


def bitknit_extra_group(value: int) -> int:
    if value < 0:
        raise ValueError("extra value must be non-negative")
    if value == 0:
        return 0
    return value.bit_length() - 1


def describe_distance_symbol(symbol: int) -> BitKnitDistanceDescriptor:
    if symbol < 0:
        raise ValueError(f"distance symbol out of range: {symbol}")
    if symbol < BITKNIT_RECENT_DISTANCE_COUNT:
        return BitKnitDistanceDescriptor(
            symbol=symbol,
            is_recent=True,
            recent_index=symbol,
            direct_index=None,
            low5=None,
            group=0,
            needs_extra_bits=False,
        )

    direct_index = symbol - BITKNIT_RECENT_DISTANCE_COUNT
    high = (direct_index >> BITKNIT_DISTANCE_LOW_BITS) + 1
    group = bitknit_extra_group(high)
    return BitKnitDistanceDescriptor(
        symbol=symbol,
        is_recent=False,
        recent_index=None,
        direct_index=direct_index,
        low5=direct_index & ((1 << BITKNIT_DISTANCE_LOW_BITS) - 1),
        group=group,
        needs_extra_bits=group != 0,
    )


def describe_direct_distance_symbols(
    long_symbol: int,
    short_symbol: int,
    extra_value: int = 0,
) -> BitKnitDirectDistanceDescriptor:
    if long_symbol < BITKNIT_RECENT_DISTANCE_COUNT:
        raise ValueError("direct distance long symbol must be >= recent count")
    if long_symbol >= BITKNIT_DLL_LONG_DISTANCE_SYMBOLS:
        raise ValueError(f"direct distance long symbol out of range: {long_symbol}")
    if short_symbol < 0 or short_symbol >= BITKNIT_DLL_SHORT_DISTANCE_SYMBOLS:
        raise ValueError(f"direct distance short symbol out of range: {short_symbol}")

    mask = (1 << short_symbol) - 1
    extra_value &= mask
    distance = (
        long_symbol
        + ((extra_value - 1) << BITKNIT_DISTANCE_LOW_BITS)
        + ((1 << (BITKNIT_DISTANCE_LOW_BITS + short_symbol)) - 7)
    )
    return BitKnitDirectDistanceDescriptor(
        long_symbol=long_symbol,
        short_symbol=short_symbol,
        extra_bits=short_symbol,
        extra_value=extra_value,
        distance=distance,
    )


def describe_length_symbol(symbol: int, extra_value: int = 0) -> BitKnitLengthDescriptor:
    if symbol < BITKNIT_SHORT_MATCH_BASE:
        raise ValueError(f"length symbol out of range: {symbol}")
    if symbol < BITKNIT_EXTRA_MATCH_BASE:
        return BitKnitLengthDescriptor(
            symbol=symbol,
            length=symbol - 0xFE,
            extra_bits=0,
            extra_value=0,
        )
    extra_bits = symbol - 0x11F
    if extra_bits <= 0:
        raise ValueError(f"length extra bit count out of range: {symbol}")
    mask = (1 << extra_bits) - 1
    extra_value &= mask
    expanded_symbol = (1 << extra_bits) + 0x11E + extra_value
    return BitKnitLengthDescriptor(
        symbol=symbol,
        length=expanded_symbol - 0xFE,
        extra_bits=extra_bits,
        extra_value=extra_value,
    )


def split_bitknit_extra_bits(value: int, bit_count: int) -> tuple[BitKnitExtraBitsRecord, ...]:
    if value < 0:
        raise ValueError("extra value must be non-negative")
    if bit_count < 0:
        raise ValueError("extra bit count must be non-negative")
    if bit_count == 0:
        return ()
    mask = (1 << bit_count) - 1
    value &= mask
    if bit_count < 16:
        return (BitKnitExtraBitsRecord(low=value, tag=0x8000 | bit_count),)
    return (
        BitKnitExtraBitsRecord(low=value >> 16, tag=0x8000 | (bit_count - 16)),
        BitKnitExtraBitsRecord(low=value & 0xFFFF, tag=0xC000),
    )


def make_dll_linear_cumulative(symbol_count: int, step: int, divisor: int) -> tuple[int, ...]:
    if symbol_count <= 0 or step <= 0 or divisor <= 0:
        raise ValueError("table parameters must be positive")
    return tuple((index * step) // divisor for index in range(symbol_count + 1))


def make_dll_literal_table_profile() -> BitKnitDllTableProfile:
    # `0x1006b3d0`: first 264 cumulative entries use a reciprocal divide by
    # 0x108, then entries 264..300 are a dense tail up to 0x8000.
    head = tuple(
        ((0x3E0F83E1 * (index * 0x7FDC)) >> 32) >> 6
        for index in range(0x108)
    )
    tail = tuple((index + 0x7ED4) & 0xFFFF for index in range(0x108, 0x12D))
    cumulative = head + tail
    return BitKnitDllTableProfile(
        cumulative=cumulative,
        update_weight=0x2D5,
        rebuild_interval=0x400,
    )


def make_dll_short_distance_table_profile() -> BitKnitDllTableProfile:
    # `0x10068aa0`: 0x15 cumulative entries, 0x3ec update weight.
    cumulative = make_dll_linear_cumulative(
        BITKNIT_DLL_SHORT_DISTANCE_SYMBOLS,
        0x8000,
        BITKNIT_DLL_SHORT_DISTANCE_SYMBOLS,
    )
    return BitKnitDllTableProfile(
        cumulative=cumulative,
        update_weight=0x3EC,
        rebuild_interval=0x400,
    )


def make_dll_long_distance_table_profile() -> BitKnitDllTableProfile:
    # `0x10068b50`: 0x28 cumulative entries, 0x3d9 update weight.
    cumulative = make_dll_linear_cumulative(
        BITKNIT_DLL_LONG_DISTANCE_SYMBOLS,
        0x8000,
        BITKNIT_DLL_LONG_DISTANCE_SYMBOLS,
    )
    return BitKnitDllTableProfile(
        cumulative=cumulative,
        update_weight=0x3D9,
        rebuild_interval=0x400,
    )


def probe_bitknit_chunk_fsm_entry(data: bytes) -> BitKnitChunkFsmCheckpoint:
    """Model the first `0x10069770` FSM decisions before compressed handler."""

    if len(data) < 2:
        raise EOFError("bitknit chunk FSM needs marker word")
    marker = struct.unpack_from("<H", data, 0)[0]
    if marker != BITKNIT2_MARKER:
        return BitKnitChunkFsmCheckpoint(
            state=-1,
            input_offset=0,
            marker=marker,
            block_word=None,
        )

    input_offset = 2
    if input_offset + 2 > len(data):
        return BitKnitChunkFsmCheckpoint(
            state=BITKNIT_FSM_CHECK_BLOCK,
            input_offset=input_offset,
            marker=marker,
            block_word=None,
        )

    block_word = struct.unpack_from("<H", data, input_offset)[0]
    if block_word == 0:
        return BitKnitChunkFsmCheckpoint(
            state=BITKNIT_FSM_COPY_EVEN,
            input_offset=input_offset + 2,
            marker=marker,
            block_word=block_word,
        )
    return BitKnitChunkFsmCheckpoint(
        state=BITKNIT_FSM_COMPRESSED,
        input_offset=input_offset,
        marker=marker,
        block_word=block_word,
    )


def sign_extend(value: int, bits: int) -> int:
    if bits <= 0:
        raise ValueError("bit count must be positive")
    sign = 1 << (bits - 1)
    mask = (1 << bits) - 1
    value &= mask
    return (value ^ sign) - sign


def peek_bitknit_header_bits(
    data: bytes,
    bit_offset: int,
    count: int,
    byte_limit: int = BITKNIT_HEADER_SIZE,
) -> int:
    if bit_offset < 0:
        raise ValueError("bit offset must be non-negative")
    if count < 0:
        raise ValueError("bit count must be non-negative")
    if count == 0:
        return 0
    if bit_offset + count > byte_limit * 8:
        raise EOFError("bitknit header bitstream exhausted")
    value = 0
    for index in range(count):
        absolute_bit = bit_offset + index
        byte_index = absolute_bit >> 3
        bit_index = absolute_bit & 7
        if byte_index >= len(data) or byte_index >= byte_limit:
            raise EOFError("bitknit header bitstream exhausted")
        bit = (data[byte_index] >> bit_index) & 1
        value |= bit << index
    return value


def read_bitknit_header_signed_byte(data: bytes, bit_offset: int) -> int:
    return sign_extend(peek_bitknit_header_bits(data, bit_offset, 8), 8)


def read_section6_fill_from_header(data: bytes, bit_offset: int) -> int:
    seed = peek_bitknit_header_bits(data, bit_offset, 8)
    return sign_extend((seed - 2) & 0xFF, 8)


def make_section6_fill_record(fill: int, size: int = BITKNIT_SECTION6_RECORD_SIZE) -> bytes:
    if size <= 0:
        raise ValueError("record size must be positive")
    fill_byte = fill & 0xFF
    first = (fill + 2) & 0xFF
    return bytes([first]) + bytes([fill_byte]) * (size - 1)


def decode_section6_fill_record_from_header(
    data: bytes,
    bit_offset: int,
    size: int = BITKNIT_SECTION6_RECORD_SIZE,
) -> bytes:
    return make_section6_fill_record(
        read_section6_fill_from_header(data, bit_offset),
        size,
    )


def decode_section6_initial_fill_records_from_header(
    data: bytes,
    bit_offset: int,
    record_count: int = BITKNIT_SECTION6_INITIAL_FILL_RECORDS,
    record_size: int = BITKNIT_SECTION6_RECORD_SIZE,
) -> bytes:
    if record_count < 0:
        raise ValueError("record count must be non-negative")
    record = decode_section6_fill_record_from_header(data, bit_offset, record_size)
    return record * record_count


def find_section6_fill_candidates(
    data: bytes,
    oracle_prefix: bytes,
    *,
    byte_limit: int = BITKNIT_HEADER_SIZE,
    min_bit_offset: int = 0,
    max_bit_offset: int | None = None,
) -> tuple[BitKnitSection6FillCandidate, ...]:
    if min_bit_offset < 0:
        raise ValueError("min bit offset must be non-negative")
    if max_bit_offset is None:
        max_bit_offset = byte_limit * 8 - 8
    if max_bit_offset < min_bit_offset:
        return ()
    candidates = []
    prefix_size = min(len(oracle_prefix), BITKNIT_SECTION6_RECORD_SIZE)
    for bit_offset in range(min_bit_offset, max_bit_offset + 1):
        try:
            seed = peek_bitknit_header_bits(data, bit_offset, 8, byte_limit)
        except EOFError:
            break
        fill = sign_extend((seed - 2) & 0xFF, 8)
        if make_section6_fill_record(fill, prefix_size) == oracle_prefix[:prefix_size]:
            candidates.append(
                BitKnitSection6FillCandidate(
                    bit_offset=bit_offset,
                    seed=seed,
                    fill=fill,
                    prefix_size=prefix_size,
            )
        )
    return tuple(candidates)


def find_section6_control_fill_candidate(
    data: bytes,
    oracle_prefix: bytes,
    *,
    byte_limit: int = BITKNIT_HEADER_SIZE,
) -> BitKnitSection6FillCandidate | None:
    """Find the first section-6 fill seed after the marker/tag header word."""

    candidates = find_section6_fill_candidates(
        data,
        oracle_prefix,
        byte_limit=byte_limit,
        min_bit_offset=32,
    )
    return candidates[0] if candidates else None


class BitKnitOutputWindow:
    """Output helper for BitKnit's modulo-4 literal and match copy paths."""

    def __init__(self, expected_size: int) -> None:
        if expected_size < 0:
            raise ValueError("expected_size must be non-negative")
        self.expected_size = expected_size
        self.data = bytearray()

    @property
    def offset(self) -> int:
        return len(self.data)

    def context_index(self) -> int:
        return self.offset & (BITKNIT_CONTEXT_STRIDE - 1)

    def append_literal_delta(self, symbol: int) -> None:
        if symbol < 0 or symbol >= BITKNIT_LITERAL_LIMIT:
            raise ValueError(f"literal symbol out of range: {symbol}")
        self._ensure_can_write(1)
        base = (
            self.data[self.offset - BITKNIT_CONTEXT_STRIDE]
            if self.offset >= BITKNIT_CONTEXT_STRIDE
            else 0
        )
        self.data.append((base + symbol) & 0xFF)

    def append_literal_from_distance(self, symbol: int, distance: int) -> None:
        if symbol < 0 or symbol >= BITKNIT_LITERAL_LIMIT:
            raise ValueError(f"literal symbol out of range: {symbol}")
        if distance <= 0:
            raise ValueError("literal distance must be positive")
        self._ensure_can_write(1)
        base = self.data[self.offset - distance] if distance <= self.offset else 0
        self.data.append((base + symbol) & 0xFF)

    def copy_match(self, distance: int, length: int) -> None:
        if distance <= 0:
            raise ValueError("match distance must be positive")
        if length < 0:
            raise ValueError("match length must be non-negative")
        if distance > self.offset:
            raise ValueError("match distance exceeds output size")
        self._ensure_can_write(length)
        for _ in range(length):
            self.data.append(self.data[self.offset - distance])

    def finish(self) -> bytes:
        if self.offset != self.expected_size:
            raise ValueError(
                f"bitknit output size mismatch: {self.offset} != {self.expected_size}"
            )
        return bytes(self.data)

    def _ensure_can_write(self, count: int) -> None:
        if self.offset + count > self.expected_size:
            raise ValueError("bitknit output exceeds expected size")


class BitKnitAdaptiveModel:
    """Small adaptive cumulative model used by the clean BitKnit decoder.

    This is an independently written model skeleton from observed behavior:
    symbols gain 31 weight per hit and the table rebuilds when the countdown
    reaches zero. The exact initial distributions still need oracle matching.
    """

    def __init__(
        self,
        symbol_count: int,
        *,
        initial_weight: int = BITKNIT_INITIAL_WEIGHT,
        update_weight: int = BITKNIT_MODEL_UPDATE,
        rebuild_interval: int | None = None,
        initial_weights: tuple[int, ...] | None = None,
    ) -> None:
        if symbol_count <= 0:
            raise ValueError("symbol_count must be positive")
        if initial_weight <= 0:
            raise ValueError("initial_weight must be positive")
        if update_weight <= 0:
            raise ValueError("update_weight must be positive")
        if initial_weights is not None and len(initial_weights) != symbol_count:
            raise ValueError("initial_weights length must match symbol_count")
        self.symbol_count = symbol_count
        self.update_weight = update_weight
        self.rebuild_interval = rebuild_interval or max(1, symbol_count)
        self.weights = (
            list(initial_weights)
            if initial_weights is not None
            else [initial_weight] * symbol_count
        )
        self.countdown = self.rebuild_interval
        self.cumulative: list[int] = []
        self.total = 0
        self.rebuild()

    def lookup(self, value: int) -> BitKnitSymbolRange:
        if value < 0 or value >= self.total:
            raise ValueError(f"model value out of range: {value}")
        symbol = bisect_right(self.cumulative, value) - 1
        return BitKnitSymbolRange(
            symbol=symbol,
            low=self.cumulative[symbol],
            high=self.cumulative[symbol + 1],
            total=self.total,
        )

    def take(self, value: int) -> BitKnitSymbolRange:
        decoded = self.lookup(value)
        self.update(decoded.symbol)
        return decoded

    def range_for(self, symbol: int) -> BitKnitSymbolRange:
        if symbol < 0 or symbol >= self.symbol_count:
            raise ValueError(f"symbol out of range: {symbol}")
        return BitKnitSymbolRange(
            symbol=symbol,
            low=self.cumulative[symbol],
            high=self.cumulative[symbol + 1],
            total=self.total,
        )

    def update(self, symbol: int) -> None:
        if symbol < 0 or symbol >= self.symbol_count:
            raise ValueError(f"symbol out of range: {symbol}")
        self.weights[symbol] += self.update_weight
        self.countdown -= 1
        if self.countdown <= 0:
            self.rescale()
        else:
            self.rebuild()

    def rescale(self) -> None:
        self.weights = [max(1, (weight + 1) // 2) for weight in self.weights]
        self.countdown = self.rebuild_interval
        self.rebuild()

    def rebuild(self) -> None:
        cumulative = [0]
        total = 0
        for weight in self.weights:
            if weight <= 0:
                raise ValueError("model weights must be positive")
            total += weight
            cumulative.append(total)
        self.cumulative = cumulative
        self.total = total


@dataclass(frozen=True)
class BitKnitModelProfile:
    literal_weights: tuple[int, ...] | None = None
    match_weights: tuple[int, ...] | None = None


BITKNIT_UNIFORM_PROFILE = BitKnitModelProfile()


def make_zero_biased_literal_profile(zero_weight: int) -> BitKnitModelProfile:
    if zero_weight <= 0:
        raise ValueError("zero_weight must be positive")
    if zero_weight == BITKNIT_INITIAL_WEIGHT:
        return BITKNIT_UNIFORM_PROFILE
    weights = (zero_weight,) + (BITKNIT_INITIAL_WEIGHT,) * (BITKNIT_LITERAL_SYMBOLS - 1)
    return BitKnitModelProfile(literal_weights=weights)


def make_literal_models(
    profile: BitKnitModelProfile = BITKNIT_UNIFORM_PROFILE,
) -> tuple[BitKnitAdaptiveModel, ...]:
    return tuple(
        BitKnitAdaptiveModel(
            BITKNIT_LITERAL_SYMBOLS,
            initial_weights=profile.literal_weights,
        )
        for _ in range(4)
    )


def make_match_models(
    profile: BitKnitModelProfile = BITKNIT_UNIFORM_PROFILE,
) -> tuple[BitKnitAdaptiveModel, ...]:
    return tuple(
        BitKnitAdaptiveModel(
            BITKNIT_MATCH_SYMBOLS,
            initial_weights=profile.match_weights,
        )
        for _ in range(4)
    )


@dataclass
class BitKnitDecoderState:
    plan: BitKnitPlan
    compressed: bytes
    literal_models: tuple[BitKnitAdaptiveModel, ...]
    match_models: tuple[BitKnitAdaptiveModel, ...]
    input_words: BitKnitWordStream
    input_chunks: BitKnitChunkStream
    range_decoder: BitKnitRangeDecoder

    def context_index(self, output_offset: int) -> int:
        return output_offset & (BITKNIT_CONTEXT_STRIDE - 1)

    def literal_model(self, output_offset: int) -> BitKnitAdaptiveModel:
        return self.literal_models[self.context_index(output_offset)]

    def match_model(self, output_offset: int) -> BitKnitAdaptiveModel:
        return self.match_models[self.context_index(output_offset)]

    def take_literal_symbol(self, output_offset: int, model_value: int) -> BitKnitSymbolRange:
        return self.literal_model(output_offset).take(model_value)

    def take_match_symbol(self, output_offset: int, model_value: int) -> BitKnitSymbolRange:
        return self.match_model(output_offset).take(model_value)

    def decode_literal_symbol(self, output_offset: int) -> BitKnitSymbolRange:
        return self.range_decoder.take_from_model(self.literal_model(output_offset))

    def decode_match_symbol(self, output_offset: int) -> BitKnitSymbolRange:
        return self.range_decoder.take_from_model(self.match_model(output_offset))

    def decode_literal_token(self, output_offset: int) -> BitKnitDecodedToken:
        decoded = self.decode_literal_symbol(output_offset)
        return BitKnitDecodedToken(
            output_offset=output_offset,
            context=self.context_index(output_offset),
            symbol_range=decoded,
            kind=classify_bitknit_symbol(decoded.symbol),
        )


def make_decoder_state(
    plan: BitKnitPlan,
    compressed: bytes,
    profile: BitKnitModelProfile = BITKNIT_UNIFORM_PROFILE,
) -> BitKnitDecoderState:
    return BitKnitDecoderState(
        plan=plan,
        compressed=compressed,
        literal_models=make_literal_models(profile),
        match_models=make_match_models(profile),
        input_words=make_word_stream(plan, compressed),
        input_chunks=make_chunk_stream(plan, compressed),
        range_decoder=make_range_decoder(plan, compressed),
    )


def parse_bitknit_plan(section: GR2Section, compressed: bytes) -> BitKnitPlan:
    if section.compression not in (COMPRESSION_BITKNIT, COMPRESSION_BITKNIT2):
        raise ValueError(f"section {section.index} is not BitKnit")
    if section.expanded_size == 0:
        return BitKnitPlan(
            section_index=section.index,
            compression_name=section.compression_name,
            compressed_size=len(compressed),
            expanded_size=section.expanded_size,
            first_16bit=section.first_16bit,
            first_8bit=section.first_8bit,
            header=None,
            payload_offset=0,
        )
    if len(compressed) < BITKNIT_HEADER_SIZE:
        raise ValueError(
            f"{section.compression_name} section {section.index} too short for header"
        )
    header = BitKnitHeader(struct.unpack_from("<12I", compressed, 0))
    return BitKnitPlan(
        section_index=section.index,
        compression_name=section.compression_name,
        compressed_size=len(compressed),
        expanded_size=section.expanded_size,
        first_16bit=section.first_16bit,
        first_8bit=section.first_8bit,
        header=header,
        payload_offset=BITKNIT_HEADER_SIZE,
    )


def make_bit_reader(plan: BitKnitPlan, compressed: bytes) -> BitKnitBitReader:
    if plan.is_empty:
        return BitKnitBitReader(compressed, 0)
    return BitKnitBitReader(compressed, plan.payload_offset)


def make_word_stream(plan: BitKnitPlan, compressed: bytes) -> BitKnitWordStream:
    if plan.is_empty:
        return BitKnitWordStream(compressed, 0)
    return BitKnitWordStream(compressed, plan.payload_offset)


def make_chunk_stream(plan: BitKnitPlan, compressed: bytes) -> BitKnitChunkStream:
    if plan.is_empty:
        return BitKnitChunkStream(compressed, 0)
    return BitKnitChunkStream(compressed, plan.payload_offset)


def make_range_decoder(plan: BitKnitPlan, compressed: bytes) -> BitKnitRangeDecoder:
    if plan.is_empty:
        return BitKnitRangeDecoder(compressed, 0, 0, 0, 0)
    return BitKnitRangeDecoder.from_payload(compressed, plan.payload_offset)


def make_header_bit_reader(
    plan: BitKnitPlan,
    compressed: bytes,
    bit_offset: int = 0,
) -> BitKnitHeaderBitReader:
    if plan.is_empty:
        return BitKnitHeaderBitReader(compressed, bit_offset, 0)
    return BitKnitHeaderBitReader(compressed, bit_offset, plan.payload_offset)


def decompress_bitknit(section: GR2Section, compressed: bytes) -> bytes:
    plan = parse_bitknit_plan(section, compressed)
    if plan.is_empty:
        return b""
    if (
        section.compression == COMPRESSION_BITKNIT
        and plan.header
        and plan.header.looks_like_bitknit2
    ):
        last_error = None
        for candidate in _classic_bitknit_state7_candidates(compressed):
            try:
                return _decode_bitknit_raw_copy_blocks(candidate, section.expanded_size)
            except DecompressionUnsupported:
                pass
            try:
                return _decode_classic_bitknit_state7_chunks(candidate, section.expanded_size)
            except (EOFError, ValueError, DecompressionUnsupported) as exc:
                last_error = exc
            try:
                result = decode_bitknit_state7_stream(candidate, section.expanded_size)
            except (EOFError, ValueError) as exc:
                last_error = exc
                continue
            if result.stopped is None and len(result.output) == section.expanded_size:
                return result.output
            last_error = DecompressionUnsupported(
                f"size={len(result.output)}/{section.expanded_size}, stopped={result.stopped}"
            )
        raise DecompressionUnsupported(
            f"{section.compression_name} native state7 decode incomplete ({last_error})"
        )
    if (
        section.compression == COMPRESSION_BITKNIT2
        and plan.header
        and plan.header.looks_like_bitknit2
    ):
        try:
            return _decode_bitknit_raw_copy_blocks(compressed, section.expanded_size)
        except DecompressionUnsupported:
            pass
        try:
            result = decode_bitknit_state7_stream(compressed, section.expanded_size)
        except (EOFError, ValueError) as exc:
            raise DecompressionUnsupported(
                f"{section.compression_name} native state7 decode stopped: {exc}"
            ) from exc
        if result.stopped is None and len(result.output) == section.expanded_size:
            return result.output
        raise DecompressionUnsupported(
            f"{section.compression_name} native state7 decode incomplete "
            f"(size={len(result.output)}/{section.expanded_size}, stopped={result.stopped})"
        )
    detail = ""
    if plan.header and plan.header.looks_like_bitknit2:
        detail = f", marker=0x{plan.header.marker:04x}, tag=0x{plan.header.header_tag:x}"
    raise DecompressionUnsupported(
        f"{section.compression_name} entropy/LZ core not implemented yet "
        f"(parsed 48-byte header{detail})"
    )


def _classic_bitknit_state7_candidates(compressed: bytes) -> tuple[bytes, ...]:
    """Return public-safe fmt3 wrapper variants that share BitKnit2 state7 core."""

    candidates = [compressed]
    if len(compressed) >= 6 and compressed[:6] == b"\xb1u\xb1u\xb1u":
        candidates.append(compressed[4:])
    if len(compressed) >= 4 and compressed[:4] == b"\xb1u\xb1u":
        candidates.append(compressed[:2] + compressed[4:])
    return tuple(candidates)


def _decode_classic_bitknit_state7_chunks(compressed: bytes, expanded_size: int) -> bytes:
    """Decode classic Granny fmt3 BitKnit chunks with per-chunk model reset."""

    output = bytearray()
    input_offset = 2
    last_error = None
    core: BitKnitState7Core | None = None
    while len(output) < expanded_size:
        if compressed[input_offset:input_offset + 2] == b"\x00\x00":
            copy_start = input_offset + 2
            copy_end = compressed.find(b"\xb1u", copy_start)
            if copy_end < 0:
                copy_end = len(compressed)
            raw = compressed[copy_start:copy_end]
            remaining = expanded_size - len(output)
            output.extend(raw[:remaining])
            input_offset = copy_end
            if len(output) >= expanded_size:
                return bytes(output)
            input_offset = _skip_classic_bitknit_marker(compressed, input_offset)
            if input_offset >= len(compressed):
                last_error = DecompressionUnsupported("classic bitknit chunk input exhausted")
                break
            core = None
            continue

        if core is None:
            core = BitKnitState7Core(compressed, expanded_size)
            core.output.data.extend(output)
            emit_initial_literal = True
        else:
            emit_initial_literal = False
        seed, decoder = core.start_block(input_offset, emit_initial_literal=emit_initial_literal)
        stopped = core.decode_block(
            decoder,
            expanded_size,
            stop_at_word_sentinel=True,
        )
        output = core.output.data
        if stopped is None and len(output) == expanded_size:
            return bytes(output)
        if stopped != "state7 block sentinel":
            last_error = DecompressionUnsupported(
                f"size={len(output)}/{expanded_size}, stopped={stopped}"
            )
            break

        input_offset = decoder.word_offset
        try:
            input_offset = _skip_classic_bitknit_marker(compressed, input_offset)
        except DecompressionUnsupported:
            pass
        else:
            core = None
        if input_offset >= len(compressed):
            last_error = DecompressionUnsupported("classic bitknit chunk input exhausted")
            break

    raise DecompressionUnsupported(
        f"classic bitknit chunk decode incomplete ({last_error})"
    )


def _skip_classic_bitknit_marker(compressed: bytes, input_offset: int) -> int:
    if compressed[input_offset:input_offset + 4] == b"\xb1u\xb1u":
        return input_offset + 4
    if compressed[input_offset:input_offset + 2] == b"\xb1u":
        return input_offset + 2
    raise DecompressionUnsupported("classic bitknit chunk marker missing")


def _decode_bitknit_raw_copy_blocks(compressed: bytes, expanded_size: int) -> bytes:
    """Decode BitKnit copy-only 64 KiB blocks seen in Granny fmt3 samples."""

    if expanded_size < 0:
        raise ValueError("expanded size must be non-negative")
    if expanded_size == 0:
        return b""
    if len(compressed) < 4 or compressed[:2] != b"\xb1u":
        raise DecompressionUnsupported("bitknit raw-copy marker missing")

    block_count = (expanded_size + BITKNIT2_BLOCK_OUTPUT_SIZE - 1) // BITKNIT2_BLOCK_OUTPUT_SIZE
    inter_block_skip = max(0, block_count - 1) * 2
    prefix_size = len(compressed) - expanded_size - inter_block_skip
    if prefix_size not in (4, 6, 8):
        raise DecompressionUnsupported(
            f"bitknit raw-copy prefix size unsupported: {prefix_size}"
        )
    if prefix_size > len(compressed):
        raise DecompressionUnsupported("bitknit raw-copy prefix exceeds input")

    output = bytearray()
    input_offset = prefix_size
    remaining = expanded_size
    for block_index in range(block_count):
        if block_index:
            input_offset += 2
        block_size = min(BITKNIT2_BLOCK_OUTPUT_SIZE, remaining)
        block_end = input_offset + block_size
        if block_end > len(compressed):
            raise DecompressionUnsupported("bitknit raw-copy block exceeds input")
        output.extend(compressed[input_offset:block_end])
        input_offset = block_end
        remaining -= block_size

    if len(output) != expanded_size:
        raise DecompressionUnsupported(
            f"bitknit raw-copy size mismatch: {len(output)}/{expanded_size}"
        )
    return bytes(output)
