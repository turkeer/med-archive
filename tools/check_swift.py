#!/usr/bin/env python3
"""Derleyici olmadan yakalanabilen hataları tarar.

Bu projede Swift derleyicisi yok; kod kör yazılıyor ve Xcode'da derleniyor.
Aşağıdaki kontroller, yaşanmış hataların her birini tek başına yakalıyor:

1. Tanımsız üye çağrısı — bir dosya yeniden yazılırken düşen fonksiyon
   (headerBackground böyle kayboldu).
2. Eksik argüman etiketi — imzası değişen bir fonksiyonun güncellenmeyen
   çağrısı (add(in:) -> add(on:in:) böyle kaldı).
3. Demet üzerinde key path — Swift buna izin vermiyor
   (ForEach(..., id: \\.offset) iki kez yazıldı).
4. Jenerik ShapeStyle konumunda zincirli baştan-nokta
   (.quaternary.opacity(...) gibi, tip çıkarımı kırılgan).
5. ForEach closure'ı içinde yerel let.

Kullanım: python3 tools/check_swift.py
"""

import os
import re
import sys

SOURCE_ROOT = 'MED'

# Swift'in kendi isimleri ve bu projede yaygın olan üye adları.
KNOWN = {
    'print', 'min', 'max', 'abs', 'stride', 'zip', 'repeatElement',
    'Array', 'String', 'Set', 'Dictionary', 'Int', 'Double', 'CGFloat', 'UUID',
    'Date', 'URL', 'Calendar', 'FileManager', 'UserDefaults', 'NSWorkspace',
    'ISO8601DateFormatter', 'FetchDescriptor', 'Binding', 'State', 'Query',
    'Color', 'Text', 'Image', 'Button', 'Label', 'Menu', 'Picker', 'Toggle',
    'TextField', 'TextEditor', 'DatePicker', 'Form', 'Section', 'List',
    'VStack', 'HStack', 'ZStack', 'Spacer', 'Divider', 'ScrollView', 'Group',
    'ForEach', 'LazyVGrid', 'GridItem', 'Circle', 'Rectangle', 'Capsule',
    'RoundedRectangle', 'GroupBox', 'DisclosureGroup', 'LabeledContent',
    'ContentUnavailableView', 'NavigationStack', 'NavigationSplitView',
    # SwiftData / Foundation üyeleri — uzantı içinden sade adla çağrılıyor
    'fetch', 'insert', 'delete', 'save', 'rollback', 'model',
    # SwiftUI View üyeleri — View uzantısı içinden self üzerinde çağrılıyor
    'labelsHidden', 'multilineTextAlignment', 'modifier',
}

KEYWORDS = {'return', 'if', 'else', 'guard', 'while', 'for', 'switch', 'case',
            'private', 'public', 'init', 'self', 'try', 'await', 'in', 'where',
            'let', 'var', 'func', 'some', 'any', 'true', 'false', 'nil',
            'inout', 'throws', 'rethrows', 'defer', 'repeat', 'as', 'is'}


def strip_noise(text):
    """Açıklamaları ve metin değişmezlerini çıkarır.

    İkisi de yanlış pozitif üretiyor: açıklamadaki "...to(..." ve metindeki
    "Ayarlar'dan (⌘,)" fonksiyon çağrısına benziyor.
    """
    text = re.sub(r'/\*.*?\*/', '', text, flags=re.S)
    text = re.sub(r'//[^\n]*', '', text)
    text = re.sub(r'"""(?:.|\n)*?"""', '""', text)
    return re.sub(r'"(?:\\.|[^"\\\n])*"', '""', text)


def signatures(code):
    """{fonksiyon adı: zorunlu etiketler} — varsayılanı olanlar atlanabilir."""
    found = {}
    for match in re.finditer(r'\bfunc\s+(\w+)\s*\(([^)]*)\)', code, re.S):
        name, params = match.group(1), match.group(2).strip()
        if not params:
            found.setdefault(name, []).append([])
            continue
        required = []
        depth = 0
        current = ''
        pieces = []
        for char in params:
            if char in '([<':
                depth += 1
            elif char in ')]>':
                depth -= 1
            if char == ',' and depth == 0:
                pieces.append(current)
                current = ''
            else:
                current += char
        pieces.append(current)
        for piece in pieces:
            piece = piece.strip()
            if not piece:
                continue
            label = piece.split(':')[0].strip().split()[0]
            if '=' in piece.split(':', 1)[-1]:
                continue           # varsayılanı var, atlanabilir
            if label == '_':
                required.append(None)
            else:
                required.append(label)
        found.setdefault(name, []).append(required)
    return found


def call_labels(code, name):
    """Bu dosyadaki `name(...)` çağrılarının etiket listeleri."""
    results = []
    for match in re.finditer(r'(?<![\w.])' + re.escape(name) + r'\s*\(', code):
        # Tanımın kendisi çağrı değil.
        if re.search(r'\bfunc\s+$', code[:match.start()]):
            continue
        index = match.end()
        depth = 1
        body = ''
        while index < len(code) and depth:
            char = code[index]
            if char in '([{':
                depth += 1
            elif char in ')]}':
                depth -= 1
                if not depth:
                    break
            body += char
            index += 1
        labels, depth = [], 0
        current = ''
        for char in body:
            if char in '([{':
                depth += 1
            elif char in ')]}':
                depth -= 1
            if char == ',' and depth == 0:
                labels.append(current)
                current = ''
            else:
                current += char
        labels.append(current)
        parsed = []
        for piece in labels:
            piece = piece.strip()
            if not piece:
                continue
            head = re.match(r'^(\w+)\s*:(?!:)', piece)
            parsed.append(head.group(1) if head else None)
        results.append(parsed)
    return results


def main():
    problems = []

    for root, _, files in os.walk(SOURCE_ROOT):
        for filename in sorted(files):
            if not filename.endswith('.swift'):
                continue

            path = os.path.join(root, filename)
            raw = open(path).read()
            code = strip_noise(raw)

            # 1. Tanımsız üye çağrısı
            defined = (set(re.findall(r'\bfunc\s+(\w+)', code))
                       | set(re.findall(r'\bvar\s+(\w+)', code))
                       | set(re.findall(r'\blet\s+(\w+)', code))
                       | set(re.findall(r'\bcase\s+(\w+)', code))
                       | set(re.findall(r'(\w+)\s*:\s*\(.*?\)\s*->', code)))
            # `@` da dışlanıyor: @escaping, @Sendable gibi niteleyiciler çağrı değil.
            called = set(re.findall(r'(?<![\w.$@])([a-z]\w*)\s*\(', code))
            for name in sorted(called - defined - KNOWN - KEYWORDS):
                problems.append(f"{filename}: '{name}(...)' tanımsız olabilir")

            # 2. Eksik argüman etiketi
            for name, variants in signatures(code).items():
                if name == 'init':
                    continue
                for labels in call_labels(code, name):
                    if any(set(v) - {None} <= set(labels) | {None} for v in variants):
                        continue
                    needed = variants[0]
                    missing = [l for l in needed if l and l not in labels]
                    if missing:
                        problems.append(
                            f"{filename}: {name}(...) çağrısında eksik etiket: {missing}")

            # 3-5. Bilinen Swift tuzakları
            if re.search(r'enumerated\(\)\s*\)\s*,\s*id:\s*\\\.', code):
                problems.append(f"{filename}: demet üzerinde key path (enumerated + id:)")
            if re.search(r'(?:foregroundStyle|background|fill|tint)\(\s*\.\w+\.\w+\(', code):
                problems.append(f"{filename}: jenerik ShapeStyle konumunda zincirli baştan-nokta")
            if re.search(r'ForEach\([^\n]*\)\s*\{[^\n]*\n\s+let\s', code):
                problems.append(f"{filename}: ForEach closure'ında yerel let")

    if problems:
        print(f"{len(problems)} bulgu:")
        for problem in problems:
            print(f"  {problem}")
        return 1

    print("temiz")
    return 0


if __name__ == '__main__':
    sys.exit(main())
