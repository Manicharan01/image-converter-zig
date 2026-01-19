import zlib
import struct

def write_png(filename, width, height):
    # Signature
    png_sig = b'\x89PNG\r\n\x1a\n'

    # IHDR
    # Width (4), Height (4), BitDepth (1), ColorType (1), Comp (1), Filter (1), Interlace (1)
    # ColorType 2 = TrueColor (RGB)
    ihdr_data = struct.pack('!IIBBBBB', width, height, 8, 2, 0, 0, 0)
    ihdr_crc = zlib.crc32(b'IHDR' + ihdr_data)
    ihdr_chunk = struct.pack('!I4s', len(ihdr_data), b'IHDR') + ihdr_data + struct.pack('!I', ihdr_crc)

    # IDAT
    # Uncompressed data: for each row, 1 filter byte (0) + width * 3 bytes (RGB)
    raw_data = b''
    for y in range(height):
        raw_data += b'\x00' # Filter type 0 (None)
        for x in range(width):
            # Red pixel
            raw_data += b'\xff\x00\x00'

    compressed_data = zlib.compress(raw_data)
    idat_crc = zlib.crc32(b'IDAT' + compressed_data)
    idat_chunk = struct.pack('!I4s', len(compressed_data), b'IDAT') + compressed_data + struct.pack('!I', idat_crc)

    # IEND
    iend_data = b''
    iend_crc = zlib.crc32(b'IEND' + iend_data)
    iend_chunk = struct.pack('!I4s', len(iend_data), b'IEND') + iend_data + struct.pack('!I', iend_crc)

    with open(filename, 'wb') as f:
        f.write(png_sig)
        f.write(ihdr_chunk)
        f.write(idat_chunk)
        f.write(iend_chunk)

    print(f"Generated {filename}")

if __name__ == "__main__":
    write_png("test.png", 10, 10)
