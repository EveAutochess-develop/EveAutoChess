"""Clean Oodle1 decompressor for Granny2 section streams."""

from __future__ import annotations

from dataclasses import dataclass

from io_scene_gr2.gr2.decompress.base import DecompressionError
from io_scene_gr2.gr2.file import GR2Section

NORM_BITS = 14
NORM_COUNT = 1 << NORM_BITS
ADJ_SUMS = NORM_COUNT << 1
MAX_LENS = 64
LOW_BITS = 2
MED_BITS = 8
ADDRESS_MASK = 3
LONG_LENGTHS = (128, 192, 256, 512)


@dataclass(frozen=True)
class _EscapeRef:
    index: int


class _ArithBits:
    def __init__(self, data: bytes):
        if not data:
            raise DecompressionError("oodle1 missing arithmetic stream")
        first = data[0]
        self.data = data
        self.ptr = 1
        self.low = first >> 1
        self.range = 1 << 7
        self.underflow = 0
        self.carry = first & 1

    def renorm(self) -> None:
        if self.range > 0x800000:
            return
        low = self.low
        rng = self.range
        carry = self.carry
        while rng <= 0x800000:
            low = ((low + low + carry) << 7) & 0xFFFFFFFF
            byte = self.data[self.ptr] if self.ptr < len(self.data) else 0
            self.ptr += 1
            low |= byte >> 1
            carry = byte & 1
            rng = (rng << 8) & 0xFFFFFFFF
        self.low = low
        self.range = rng
        self.carry = carry

    def get_bits(self, bits: int, scale: int) -> int:
        self.renorm()
        self.underflow = self.range >> bits
        value = self.low // self.underflow if self.underflow else 0
        return scale - 1 if value >= scale else value

    def get_bits_value(self, bits: int, scale: int) -> int:
        self.renorm()
        divisor = self.range >> bits
        value = self.low // divisor if divisor else 0
        if value >= scale:
            value = scale - 1
        offset = (divisor * value) & 0xFFFFFFFF
        self.low = (self.low - offset) & 0xFFFFFFFF
        self.range = divisor if value + 1 < scale else (self.range - offset) & 0xFFFFFFFF
        return value

    def get_value(self, scale: int) -> int:
        self.renorm()
        divisor = self.range // scale if scale else 0
        value = self.low // divisor if divisor else 0
        if value >= scale:
            value = scale - 1
        offset = (divisor * value) & 0xFFFFFFFF
        self.low = (self.low - offset) & 0xFFFFFFFF
        self.range = divisor if value + 1 < scale else (self.range - offset) & 0xFFFFFFFF
        return value

    def remove(self, start: int, count: int, scale: int) -> None:
        offset = (self.underflow * start) & 0xFFFFFFFF
        self.low = (self.low - offset) & 0xFFFFFFFF
        if start + count < scale:
            self.range = (self.underflow * count) & 0xFFFFFFFF
        else:
            self.range = (self.range - offset) & 0xFFFFFFFF


class _ArithModel:
    def __init__(self, max_value: int, unique_count: int):
        self.unique_count = unique_count
        size = max(max_value, unique_count) + 16
        self.values = [0] * size
        self.single_counts = [0] * (size + 16)
        self.summed_counts = [NORM_COUNT + ADJ_SUMS] * (size + 32)
        self.singles_tot = 4
        self.update_tot = 8
        self.update_range = 4
        self.rescale_tot = min(max(max_value * 32, 256), 15160)
        update_max = max_value * 2
        if update_max < 128:
            update_max = 128
        else:
            cap = (self.rescale_tot >> 1) - 32
            if update_max > cap:
                update_max = cap
        self.update_max = max(0, update_max)
        self.singles_length = 0
        self.summed_length = 0
        self.single_counts[0] = 4
        self.summed_counts[0] = ADJ_SUMS
        for index in range(1, 6):
            self.summed_counts[index] = NORM_COUNT + ADJ_SUMS

    def _rescale(self) -> None:
        self.single_counts[0] >>= 1
        self.singles_tot = self.single_counts[0]
        max_count = 0
        max_pos = 0
        index = 1
        while index <= self.singles_length:
            while self.single_counts[index] <= 1:
                if index < self.singles_length:
                    self.single_counts[index] = self.single_counts[self.singles_length]
                    self.single_counts[self.singles_length] = 0
                    self.values[index] = self.values[self.singles_length]
                    self.singles_length -= 1
                else:
                    self.single_counts[index] = 0
                    self.singles_length -= 1
                    break
            if index > self.singles_length:
                break
            self.single_counts[index] >>= 1
            self.singles_tot += self.single_counts[index]
            if self.single_counts[index] > max_count:
                max_count = self.single_counts[index]
                max_pos = index
            index += 1
        if max_count and self.singles_length:
            last = self.singles_length
            if max_pos != last:
                self.single_counts[last], self.single_counts[max_pos] = (
                    self.single_counts[max_pos],
                    self.single_counts[last],
                )
                self.values[last], self.values[max_pos] = self.values[max_pos], self.values[last]
        if self.singles_length != self.unique_count and self.single_counts[0] == 0:
            self.single_counts[0] += 1
            self.singles_tot += 1

    def _update_counts(self) -> None:
        adj = (NORM_COUNT * 8) // max(self.singles_tot, 1)
        total = (((self.single_counts[0]) * adj) >> 3) + ADJ_SUMS
        self.summed_counts[0] = ADJ_SUMS
        index = 1
        while True:
            self.summed_counts[index] = total
            if index > self.singles_length:
                break
            total += ((self.single_counts[index] * adj) >> 3)
            index += 1
        next_range = self.update_range << 1
        if next_range > self.update_max:
            self.update_tot = self.singles_tot + self.update_max
        else:
            self.update_range = next_range
            self.update_tot = self.singles_tot + next_range
        self.summed_length = self.singles_length
        for pad in range(1, 8):
            self.summed_counts[self.summed_length + pad] = NORM_COUNT + ADJ_SUMS

    def decode(self, bits: _ArithBits) -> int | _EscapeRef:
        if self.singles_tot >= self.update_tot:
            if self.update_tot >= self.rescale_tot:
                self._rescale()
            self._update_counts()

        offset = bits.get_bits(NORM_BITS, NORM_COUNT) + ADJ_SUMS
        low = 0
        high = self.summed_length + 1
        while low < high:
            mid = (low + high + 1) >> 1
            if self.summed_counts[mid] > offset:
                high = mid - 1
            else:
                low = mid
        index = low
        bits.remove(
            self.summed_counts[index] - ADJ_SUMS,
            self.summed_counts[index + 1] - self.summed_counts[index],
            NORM_COUNT,
        )
        self.single_counts[index] += 1
        self.singles_tot += 1

        if index <= 0:
            if self.singles_length == self.summed_length or bits.get_bits_value(1, 2) == 0:
                index = self._new_index()
                return _EscapeRef(index)
            index = bits.get_value(self.singles_length - self.summed_length) + self.summed_length + 1
            if index < len(self.single_counts):
                self.single_counts[index] += 2
                self.singles_tot += 2
            return self.values[index] if index < len(self.values) else 0
        return self.values[index]

    def _new_index(self) -> int:
        if self.singles_length >= len(self.single_counts) - 1:
            return 0
        self.singles_length += 1
        index = self.singles_length
        self.single_counts[index] += 2
        self.singles_tot += 2
        if self.singles_length == self.unique_count:
            self.singles_tot -= self.single_counts[0]
            self.single_counts[0] = 0
        return index

    def set_decompressed_symbol(self, ref: _EscapeRef, value: int) -> None:
        if ref.index >= len(self.values):
            self.values.extend([0] * (ref.index + 1 - len(self.values)))
        self.values[ref.index] = value


def _decode_symbol(model: _ArithModel, bits: _ArithBits, escape_scale: int) -> int:
    value = model.decode(bits)
    if isinstance(value, _EscapeRef):
        escaped = bits.get_value(escape_scale)
        model.set_decompressed_symbol(value, escaped)
        return escaped
    return value


def _u32le(data: bytes, offset: int) -> int:
    return int.from_bytes(data[offset : offset + 4], "little")


def _top_offset(value: int) -> int:
    return value >> (LOW_BITS + MED_BITS)


def _init_lz_models(header: bytes):
    max_offset_and_byte = _u32le(header, 0)
    unique_offset_and_byte = _u32le(header, 4)
    unique_lengths = _u32le(header, 8)
    max_byte = max_offset_and_byte & 0x1FF
    max_offset = max_offset_and_byte >> 9
    unique_byte = unique_offset_and_byte & 0x1FF
    low_count = min(max_offset + 1, 1 << LOW_BITS)
    mid_count = min((max_offset >> LOW_BITS) + 1, 1 << MED_BITS)
    high_count = _top_offset(max_offset) + 1
    byte_models = [_ArithModel(max_byte - 1, unique_byte) for _ in range(ADDRESS_MASK + 1)]
    length_models = []
    last_unique = 0
    for group in range(4):
        last_unique = (unique_lengths >> ((3 - group) * 8)) & 0xFF
        for _ in range(MAX_LENS // 4):
            length_models.append(_ArithModel(MAX_LENS, last_unique))
    for _ in range((MAX_LENS // 4) * 4, MAX_LENS + 1):
        length_models.append(_ArithModel(MAX_LENS, last_unique))
    offset_low = _ArithModel(low_count - 1, low_count)
    offset_high = _ArithModel(high_count - 1, _top_offset(unique_offset_and_byte >> 9) + 1)
    offset_mid = [_ArithModel(mid_count - 1, mid_count) for _ in range(high_count)]
    return byte_models, length_models, offset_low, offset_high, offset_mid, max_byte, max_offset, low_count, mid_count


def _decode_lz_block(models, bits: _ArithBits, output: bytearray, start: int, stop: int) -> int:
    byte_models, length_models, offset_low, offset_high, offset_mid, max_byte, max_offset_limit, low_count, mid_count = models
    last_length = 0
    pos = start
    bytes_decompressed = 0
    while pos < stop:
        length_symbol = _decode_symbol(length_models[min(last_length, MAX_LENS)], bits, MAX_LENS + 1)
        last_length = length_symbol
        if length_symbol:
            max_offset = min(max_offset_limit, bytes_decompressed)
            length = LONG_LENGTHS[length_symbol - (MAX_LENS - 3)] if length_symbol >= MAX_LENS - 3 else length_symbol + 1
            low = _decode_symbol(offset_low, bits, low_count)
            high = _decode_symbol(offset_high, bits, _top_offset(max_offset) + 1)
            if max_offset >= ((1 << MED_BITS) << LOW_BITS):
                mid_scale = 1 << MED_BITS
            else:
                mid_scale = (max_offset >> LOW_BITS) + 1
            mid = _decode_symbol(offset_mid[high], bits, mid_scale)
            distance = low + 1 + (mid << LOW_BITS) + (high << (LOW_BITS + MED_BITS))
            for _ in range(length):
                if pos < len(output) and pos >= distance:
                    output[pos] = output[pos - distance]
                pos += 1
            bytes_decompressed += length
        else:
            output[pos] = _decode_symbol(byte_models[pos & ADDRESS_MASK], bits, max_byte) & 0xFF
            pos += 1
            bytes_decompressed += 1
    return pos


def decompress_oodle1(section: GR2Section, compressed: bytes) -> bytes:
    if section.expanded_size == 0:
        return b""
    if len(compressed) < 36:
        raise DecompressionError("oodle1 data too short for 3 block headers")
    bits = _ArithBits(compressed[36:])
    output = bytearray(section.expanded_size)
    pos = 0
    for block_index, stop in enumerate((section.first_16bit, section.first_8bit, section.expanded_size)):
        if pos >= stop:
            if block_index == 2:
                break
            continue
        models = _init_lz_models(compressed[block_index * 12 : block_index * 12 + 12])
        pos = _decode_lz_block(models, bits, output, pos, min(stop, section.expanded_size))
    if pos < section.expanded_size:
        raise DecompressionError(f"oodle1 decompressed {pos}, expected {section.expanded_size}")
    return bytes(output)
