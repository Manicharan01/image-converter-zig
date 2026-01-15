import zlib

with open("./compressed.bin", "rb") as file:
    compressed = file.read()

decompressed = zlib.decompress(compressed)

with open("python_output.bin", "wb") as f:
    f.write(decompressed)

print(f"Python wrote to python_output.bin")
