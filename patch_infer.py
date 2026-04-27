import os

patches = {
    os.path.join('vc', 'passes', 'infer.cc'): '#include <snmalloc/ds_core/defines.h>\n',
    os.path.join('vc', 'passes', 'parser.cc'): '#pragma GCC diagnostic ignored "-Wdeprecated-declarations"\n',
    os.path.join('vbci', 'value.h'): '#pragma GCC diagnostic ignored "-Wshadow"\n',
    os.path.join('vbci', 'header.h'): '#pragma GCC diagnostic ignored "-Wshadow"\n',
    os.path.join('vbci', 'object.h'): '#pragma GCC diagnostic ignored "-Wshadow"\n',
    os.path.join('vbcc', 'bytecode.h'): '#pragma GCC diagnostic ignored "-Wshadow"\n',
    os.path.join('vbcc', 'bytecode.cc'): '#pragma GCC diagnostic ignored "-Wshadow"\n',
}

for path, prefix in patches.items():
    if not os.path.exists(path):
        print(f"Skipping {path} (not found)")
        continue
    with open(path, 'r') as f:
        c = f.read()
    if prefix.strip() not in c:
        with open(path, 'w') as f:
            f.write(prefix + c)