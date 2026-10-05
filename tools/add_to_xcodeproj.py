#!/usr/bin/env python3
"""MED.xcodeproj'a Swift dosyası ekler.

Proje dosyası elle yazıldı (klasik biçim, objectVersion 56) ve Xcode 15'ten
itibaren açılıyor. Yeni dosya eklemek pbxproj'da üç yere dokunmak demek:
PBXFileReference, PBXBuildFile ve Sources derleme fazı — artı dosyanın
bulunduğu PBXGroup. Bu araç dördünü birden, tutarlı kimliklerle yapıyor.

Kullanım:
    python3 tools/add_to_xcodeproj.py MED/Views/Foo.swift MED/Support/Bar.swift

Kimlikler "ED" + 18 sıfır + 4 haneli sayaç biçiminde; sayaç dosya
referansları için 01xx, derleme girdileri için 02xx serisinden ilerliyor.
"""

import os
import re
import sys

PROJECT = 'MED.xcodeproj/project.pbxproj'

# Diskteki klasör -> pbxproj grup kimliği
GROUPS = {
    'MED':                  ('0010', 'MED'),
    'MED/Models':           ('0011', 'Models'),
    'MED/Views':            ('0012', 'Views'),
    'MED/Support':          ('0013', 'Support'),
    'MED/Views/Components': ('0014', 'Components'),
}


def oid(suffix):
    return 'ED' + '0' * 18 + suffix


def next_free(src, series):
    """Verilen seride (01 ya da 02) kullanılmayan ilk sayacı bulur."""
    used = {
        int(m, 16)
        for m in re.findall(r'ED0{18}(' + series + r'[0-9A-F]{2})\b', src)
    }
    counter = int(series + '01', 16)
    while counter in used:
        counter += 1
    return format(counter, '04X')


def quoted(name):
    return name if re.fullmatch(r'[A-Za-z0-9_.]+', name) else f'"{name}"'


def add(src, path):
    directory, name = os.path.split(path)
    if directory not in GROUPS:
        raise SystemExit(f"bilinmeyen klasör: {directory} — GROUPS'a ekle")
    if not os.path.exists(path):
        raise SystemExit(f"diskte yok: {path}")
    if f'/* {name} */' in src:
        print(f"  zaten ekli, atlandı: {path}")
        return src

    file_id, build_id = oid(next_free(src, '01')), oid(next_free(src, '02'))
    group_id, group_label = GROUPS[directory]

    src = src.replace(
        '/* End PBXBuildFile section */',
        f'        {build_id} /* {name} in Sources */ = {{isa = PBXBuildFile; '
        f'fileRef = {file_id} /* {name} */; }};\n'
        '/* End PBXBuildFile section */')

    src = src.replace(
        '/* End PBXFileReference section */',
        f'        {file_id} /* {name} */ = {{isa = PBXFileReference; '
        f'lastKnownFileType = sourcecode.swift; path = {quoted(name)}; '
        f'sourceTree = "<group>"; }};\n'
        '/* End PBXFileReference section */')

    pattern = re.compile(
        r'(' + oid(group_id) + r' /\* ' + re.escape(group_label) +
        r' \*/ = \{\n            isa = PBXGroup;\n            children = \(\n)')
    src, count = pattern.subn(
        lambda m: m.group(1) + f'                {file_id} /* {name} */,\n', src)
    if count != 1:
        raise SystemExit(f"{group_label} grubu bulunamadı")

    pattern = re.compile(r'(' + oid('0006') + r' /\* Sources \*/ = \{.*?files = \(\n)', re.S)
    src, count = pattern.subn(
        lambda m: m.group(1) + f'                {build_id} /* {name} in Sources */,\n', src)
    if count != 1:
        raise SystemExit("Sources fazı bulunamadı")

    print(f"  eklendi: {path}  ({file_id})")
    return src


def main(paths):
    if not paths:
        raise SystemExit(__doc__)
    src = open(PROJECT).read()
    for path in paths:
        src = add(src, path.lstrip('./'))
    open(PROJECT, 'w').write(src)


if __name__ == '__main__':
    main(sys.argv[1:])
