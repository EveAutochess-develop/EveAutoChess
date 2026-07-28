"""Clean Oodle0 decompressor for Granny2 section streams."""

from __future__ import annotations

import struct
from dataclasses import dataclass

from io_scene_gr2.gr2.decompress.base import DecompressionError
from io_scene_gr2.gr2.file import GR2Section

OODLE0_HEADER_SIZE = 36
OODLE0_BLOCK_COUNT = 3
OFFSET_SPLIT_SHIFT = 2
LOW_OFFSET_MASK = (1 << OFFSET_SPLIT_SHIFT) - 1
MAX_LENS = 64
LONG_LENGTHS = (MAX_LENS * 2, MAX_LENS * 3, MAX_LENS * 4, MAX_LENS * 8)
MASK32 = 0xFFFFFFFF
MASK31 = 0x7FFFFFFF
_OFFSET_BYTE_MASK = 0x1FF


@dataclass(frozen=True)
class Oodle0LZHeader:
    max_offset_and_byte: int
    uniq_offset_and_byte: int
    uniq_lens: int

    @property
    def max_byte_value(self) -> int:
        return self.max_offset_and_byte & _OFFSET_BYTE_MASK

    @property
    def max_offset(self) -> int:
        return self.max_offset_and_byte >> 9

    @property
    def unique_byte_values(self) -> int:
        return self.uniq_offset_and_byte & _OFFSET_BYTE_MASK

    @property
    def unique_offsets(self) -> int:
        return self.uniq_offset_and_byte >> 9

    @property
    def unique_length_contexts(self) -> tuple[int, int, int, int]:
        return tuple((self.uniq_lens >> (index * 8)) & 0xFF for index in range(4))

    def to_dict(self) -> dict:
        return {
            "max_byte_value": self.max_byte_value,
            "max_offset": self.max_offset,
            "unique_byte_values": self.unique_byte_values,
            "unique_offsets": self.unique_offsets,
            "unique_length_contexts": list(self.unique_length_contexts),
        }

    def length_unique(self, index: int) -> int:
        group = min(index // (MAX_LENS // 4), 3)
        return (self.uniq_lens >> ((3 - group) * 8)) & 0xFF


@dataclass(frozen=True)
class Oodle0Block:
    index: int
    output_start: int
    output_end: int
    header: Oodle0LZHeader

    @property
    def output_size(self) -> int:
        return max(0, self.output_end - self.output_start)

    @property
    def is_empty(self) -> bool:
        return self.output_size == 0

    def to_dict(self) -> dict:
        return {
            "index": self.index,
            "output_start": self.output_start,
            "output_end": self.output_end,
            "output_size": self.output_size,
            "header": self.header.to_dict(),
        }


@dataclass(frozen=True)
class Oodle0Plan:
    section_index: int
    expanded_size: int
    blocks: tuple[Oodle0Block, ...]
    bitstream_offset: int = OODLE0_HEADER_SIZE

    def to_dict(self) -> dict:
        return {
            "section_index": self.section_index,
            "expanded_size": self.expanded_size,
            "bitstream_offset": self.bitstream_offset,
            "blocks": [block.to_dict() for block in self.blocks],
        }


def parse_oodle0_plan(section: GR2Section, compressed: bytes) -> Oodle0Plan:
    if len(compressed) < OODLE0_HEADER_SIZE:
        raise ValueError(f"oodle0 section {section.index} too short for header")
    words = struct.unpack_from("<9I", compressed, 0)
    headers = tuple(
        Oodle0LZHeader(*words[index * 3 : index * 3 + 3])
        for index in range(OODLE0_BLOCK_COUNT)
    )
    stops = _block_stops(section)
    blocks = tuple(
        Oodle0Block(
            index=index,
            output_start=stops[index],
            output_end=stops[index + 1],
            header=headers[index],
        )
        for index in range(OODLE0_BLOCK_COUNT)
    )
    return Oodle0Plan(
        section_index=section.index,
        expanded_size=section.expanded_size,
        blocks=blocks,
    )


class _VarBits:
    def __init__(self, data: bytes, offset: int):
        self.data = data
        self.cur = offset
        self.bits = 0
        self.bitlen = 0

    def get(self, nbits: int) -> int:
        if nbits == 0:
            return 0
        mask = (1 << nbits) - 1
        if self.bitlen >= nbits:
            value = self.bits & mask
            self.bits >>= nbits
            self.bitlen -= nbits
            return value
        word = _u32le_padded(self.data, self.cur)
        self.cur += 4
        value = (self.bits | (word << self.bitlen)) & mask
        self.bits = word >> (nbits - self.bitlen)
        self.bitlen = self.bitlen + 32 - nbits
        return value

    def get1(self) -> int:
        if self.bitlen:
            value = self.bits & 1
            self.bits >>= 1
            self.bitlen -= 1
            return value
        word = _u32le_padded(self.data, self.cur)
        self.cur += 4
        self.bits = word >> 1
        self.bitlen = 31
        return word & 1


class _ArithBits:
    def __init__(self, data: bytes, offset: int):
        self.vbits = _VarBits(data, offset)
        self.high = MASK31
        self.low = 0
        self.code = _bit_reverse(self.vbits.get(31), 31)

    def get_count(self, scale: int) -> int:
        if scale <= 0:
            return 0
        return ((((self.code - self.low) + 1) * scale) - 1) // ((self.high - self.low) + 1)

    def get_value(self, scale: int) -> int:
        value = self.get_count(scale)
        if value >= scale:
            value = scale - 1
        self.remove(value, 1, scale)
        return value

    def remove(self, start: int, count: int, scale: int) -> None:
        if scale <= 0:
            return
        high = self.high
        low = self.low
        code = self.code
        width = (high - low) + 1
        high = _u32(low + ((width * (start + count)) // scale) - 1)
        low = _u32(low + ((width * start) // scale))
        if ((high ^ low) & 0x40000000) == 0:
            while ((high ^ low) & 0x7F800000) == 0:
                low = _u32(low << 8)
                high = _u32((high << 8) | 0xFF)
                byte = self.vbits.get(8)
                code = _u32((code << 8) | (_bit_reverse(byte & 0xF, 4) << 4) | _bit_reverse(byte >> 4, 4))
            if ((high ^ low) & 0x78000000) == 0:
                low = _u32(low << 4)
                high = _u32((high << 4) | 0xF)
                code = _u32((code << 4) | _bit_reverse(self.vbits.get(4), 4))
            while ((high ^ low) & 0x40000000) == 0:
                low = _u32(low << 1)
                high = _u32((high << 1) | 1)
                code = _u32((code << 1) | self.vbits.get1())
        while (low & 0x20000000) and not (high & 0x20000000):
            code = _u32(code ^ 0x20000000)
            low = _u32((low & 0x1FFFFFFF) << 1)
            high = _u32((high << 1) | 0x40000001)
            code = _u32((code << 1) | self.vbits.get1())
        self.high = high & MASK31
        self.low = low & MASK31
        self.code = code & MASK31


class _EscapeSymbol:
    def __init__(self, index: int):
        self.index = index


class _ArithModel:
    def __init__(self, unique_values: int):
        self.unique_values = unique_values
        count = _aligned_count(unique_values)
        self.totals = [0] * 16
        self.counts = [0] * count
        self.values = [0] * count
        self.number = 0
        self.bin_size, self.bin_shift, self.last_bin_start = _best_shift(unique_values + 1)
        self._quick_increment(0, 0x30003)

    def decompress(self, bits: _ArithBits) -> int | _EscapeSymbol:
        if self.totals[15] >= 16384:
            self._rescale()
        scale = self.totals[15]
        count = bits.get_count(scale)
        pos, start = self._find_pos(count)
        old_count = self.counts[pos]
        self._increment_totals(pos, 0x10001)
        bits.remove(start, old_count, self.totals[15] - 1)
        self.counts[pos] = _u16(self.counts[pos] + 1)
        if pos == 0:
            self.number += 1
            if self.number >= len(self.counts):
                raise DecompressionError("oodle0 escape exceeded model capacity")
            self._quick_increment(self.number, 0x20002)
            if self.number == self.unique_values:
                self._decrement_counts(0, self.counts[0])
            return _EscapeSymbol(self.number)
        return self.values[pos]

    def set_escaped(self, marker: _EscapeSymbol, value: int) -> None:
        self.values[marker.index] = _u16(value)

    def _find_pos(self, count: int) -> tuple[int, int]:
        start = 0
        for pos, entry_count in enumerate(self.counts):
            if count < start + entry_count:
                return pos, start
            start += entry_count
        raise DecompressionError(f"oodle0 model count {count} outside total {start}")

    def _quick_increment(self, value: int, amount: int) -> None:
        self._increment_totals(value, amount)
        self.counts[value] = _u16(self.counts[value] + (amount & 0xFFFF))

    def _increment_totals(self, value: int, amount: int) -> None:
        amount &= MASK32
        low = amount & 0xFFFF
        if value >= self.last_bin_start:
            self.totals[15] = _u16(self.totals[15] + low)
            return
        bin_index = value >> self.bin_shift
        if bin_index & 1:
            self.totals[bin_index] = _u16(self.totals[bin_index] + low)
            bin_index += 1
        for pair_index in range(bin_index >> 1, 8):
            self._add_total_pair_u32(pair_index, amount)

    def _add_total_pair_u32(self, pair_index: int, amount: int) -> None:
        index = pair_index * 2
        old = self.totals[index] | (self.totals[index + 1] << 16)
        new = (old + amount) & MASK32
        self.totals[index] = new & 0xFFFF
        self.totals[index + 1] = (new >> 16) & 0xFFFF

    def _decrement_counts(self, value: int, amount: int) -> None:
        neg = (-amount) & MASK32
        packed = (((neg - 1) & MASK32) << 16) | (neg & 0xFFFF)
        self._quick_increment(value, packed)

    def _rescale(self) -> None:
        self.bin_size, self.bin_shift, self.last_bin_start = _best_shift(self.number + 1)
        bins = [0] * 16
        self.counts[0] >>= 1
        bins[0 if 0 < self.last_bin_start else 15] += self.counts[0]
        max_count = 0
        max_pos = 0
        index = 1
        done = False
        while index <= self.number and not done:
            while self.counts[index] <= 1:
                if index < self.number:
                    self.counts[index] = self.counts[self.number]
                    self.values[index] = self.values[self.number]
                    self.counts[self.number] = 0
                    self.number -= 1
                else:
                    self.counts[index] = 0
                    self.number -= 1
                    done = True
                    break
            if done:
                break
            self.counts[index] >>= 1
            if self.counts[index] > max_count:
                max_count = self.counts[index]
                max_pos = index
            bins[(index >> self.bin_shift) if index < self.last_bin_start else 15] += self.counts[index]
            index += 1
        if max_count:
            swap_pos = ((self.number >> self.bin_shift) << self.bin_shift) if self.number < self.last_bin_start else self.last_bin_start
            if swap_pos == 0:
                swap_pos = 1
            if max_pos != swap_pos:
                old_count = self.counts[swap_pos]
                self.counts[swap_pos] = self.counts[max_pos]
                bins[(swap_pos >> self.bin_shift) if swap_pos < self.last_bin_start else 15] += -old_count + self.counts[swap_pos]
                bins[(max_pos >> self.bin_shift) if max_pos < self.last_bin_start else 15] += old_count - self.counts[swap_pos]
                self.counts[max_pos] = old_count
                self.values[swap_pos], self.values[max_pos] = self.values[max_pos], self.values[swap_pos]
        if self.number != self.unique_values and self.counts[0] == 0:
            self.counts[0] = _u16(self.counts[0] + 2)
            bins[0 if 0 < self.last_bin_start else 15] += 2
        running = 0
        for index, value in enumerate(bins):
            running += value
            self.totals[index] = _u16(running)


class _LZState:
    def __init__(self, header: Oodle0LZHeader):
        self.max_bytes = header.max_byte_value
        self.max_offsets = header.max_offset
        self.max_offset_low = min(self.max_offsets, LOW_OFFSET_MASK + 1)
        self.bytes = _ArithModel(header.unique_byte_values)
        self.lengths = [_ArithModel(header.length_unique(index)) for index in range(MAX_LENS + 1)]
        self.offset_low = _ArithModel(self.max_offset_low)
        self.offset_high = _ArithModel(header.unique_offsets)
        self.bytes_decompressed = 0
        self.last_length = 0


def decompress_oodle0(section: GR2Section, compressed: bytes) -> bytes:
    if section.expanded_size == 0:
        return b""
    if len(compressed) < OODLE0_HEADER_SIZE:
        raise DecompressionError("oodle0 data too short for 3 block headers")
    plan = parse_oodle0_plan(section, compressed)
    bits = _ArithBits(compressed, OODLE0_HEADER_SIZE)
    output = bytearray()
    for block in plan.blocks:
        if block.is_empty:
            continue
        state = _LZState(block.header)
        _decode_block(state, bits, output, block.output_end)
    if len(output) != section.expanded_size:
        raise DecompressionError(f"oodle0 decompressed {len(output)}, expected {section.expanded_size}")
    return bytes(output)


def _decode_block(state: _LZState, bits: _ArithBits, output: bytearray, stop: int) -> None:
    while len(output) < stop:
        previous_length = state.last_length
        length_symbol = _read_model_symbol(state.lengths[previous_length], bits, MAX_LENS + 1)
        state.last_length = length_symbol
        if length_symbol:
            length = (
                LONG_LENGTHS[length_symbol - (MAX_LENS - 3)]
                if length_symbol >= MAX_LENS - 3
                else length_symbol + 1
            )
            low = _read_model_symbol(state.offset_low, bits, state.max_offset_low)
            high_scale = (min(state.max_offsets, state.bytes_decompressed) >> OFFSET_SPLIT_SHIFT) + 1
            high = _read_model_symbol(state.offset_high, bits, high_scale)
            distance = low + 1 + (high << OFFSET_SPLIT_SHIFT)
            if distance <= 0 or distance > len(output):
                raise DecompressionError(f"oodle0 invalid copy distance {distance}")
            for _ in range(length):
                output.append(output[-distance])
            state.bytes_decompressed += length
        else:
            literal = _read_model_symbol(state.bytes, bits, state.max_bytes)
            if not 0 <= literal <= 255:
                raise DecompressionError(f"oodle0 invalid literal {literal}")
            output.append(literal)
            state.bytes_decompressed += 1


def _read_model_symbol(model: _ArithModel, bits: _ArithBits, escape_scale: int) -> int:
    value = model.decompress(bits)
    if isinstance(value, _EscapeSymbol):
        escaped = bits.get_value(escape_scale)
        model.set_escaped(value, escaped)
        return escaped
    return int(value)


def _block_stops(section: GR2Section) -> tuple[int, int, int, int]:
    expanded = section.expanded_size
    first_16bit = _clamp_stop(section.first_16bit, expanded)
    first_8bit = _clamp_stop(section.first_8bit, expanded)
    if first_8bit < first_16bit:
        first_8bit = first_16bit
    return 0, first_16bit, first_8bit, expanded


def _clamp_stop(value: int, expanded_size: int) -> int:
    if value <= 0:
        return 0
    if value >= expanded_size:
        return expanded_size
    return value


def _u16(value: int) -> int:
    return value & 0xFFFF


def _u32(value: int) -> int:
    return value & MASK32


def _u32le_padded(data: bytes, offset: int) -> int:
    if offset + 4 > len(data):
        chunk = data[offset:] + b"\x00" * (offset + 4 - len(data))
    else:
        chunk = data[offset : offset + 4]
    return int.from_bytes(chunk, "little")


def _bit_reverse(value: int, nbits: int) -> int:
    result = 0
    for index in range(nbits):
        result = (result << 1) | ((value >> index) & 1)
    return result


def _aligned_count(unique_values: int) -> int:
    return (unique_values + 5) & ~3


def _best_shift(value: int) -> tuple[int, int, int]:
    if value < 6:
        return 0, 15, 0
    best_max = MASK32
    best_bin = 0
    for index in range(16):
        size = 1 << index
        bins = min((value + size - 1) // size, 16)
        last = value - (size * (bins - 1))
        if last < size:
            last = size
        if last < best_max:
            best_bin = index
            best_max = last
        if size > value:
            break
    bin_size = 1 << best_bin
    return bin_size, best_bin, 15 * bin_size
