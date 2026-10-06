# Development notes

*[Türkçe / Turkish](GELISTIRME.md)*

For anyone reading or changing the code. To *use* the app, the
[README](../README.md) is enough.

The Turkish [GELISTIRME.md](GELISTIRME.md) is the long one: it documents every
architectural decision and the pitfall behind it. This file is the short
English orientation.

## Building

macOS 14 or later, Xcode 15 or later. **No Apple Developer account needed.**

```
git clone https://github.com/turkeer/med-archive.git
cd med-archive
open MED.xcodeproj
```

Press ⌘R. `CODE_SIGN_IDENTITY = "-"` (ad-hoc) and the App Sandbox is off, so
there is nothing to provision.

## The shape of it

SwiftUI + SwiftData, macOS 14+, one `NavigationSplitView` with three columns.
Seven `@Model` types: `Lecture` (the centre of it), `Course`, `Instructor`,
`Committee`, `Tag`, `LectureFile`, `PastExam`.

`MED/Models` is the store, `MED/Support` is the logic that has no view in it,
`MED/Views` is everything else.

## Five things to know before you change anything

**1. Adding an attribute to a model is not free.** SwiftData does not backfill
a new attribute with its Swift default: existing rows keep NULL, and reading
NULL into a non-optional `Codable` enum crashes on the **first row read** — not
at container creation, so the app launches, shows a Dock icon and no window.
That is why `Lecture.formatRaw` is a private optional with a computed accessor
over it. Plain types (String, Int) are safe; their default lives in the store
metadata.

**2. Derived, not stored.** Period numbers, topic grouping, part numbers
(1/2), the committee a date falls in, file sharing between the parts of a
topic — all computed from what is already there. Nothing to migrate, nothing
to keep in sync. Keep it that way.

**3. Sessions store real times, not period numbers.** `LessonSlot` is derived
from `startMinutes`/`endMinutes`. This is what makes the timetable safe to
change: edit the table and no record migrates; one that no longer lines up
simply reads as a custom time.

**4. `MED.xcodeproj/project.pbxproj` is hand-written.** A new source file needs
four entries, not one. Use the script:

```
python3 tools/add_to_xcodeproj.py MED/Support/NewThing.swift
```

A Resources build phase exists, but the script only handles Sources — an asset
catalog (e.g. an app icon) has to be added to Resources by hand.

**5. Translation is at the point of use.** `L.pick("Konular", "Topics")`, not a
key-and-table. Both languages are arguments of the same call, so a missing one
is a compile error rather than a key that falls through to its own name at
runtime. Only words used in several places get a name in `L`.

Text matching folds Turkish letters explicitly (`ı` has no diacritic to strip,
so it would never fold to `i`). Folding is for **matching**;
`localizedStandardCompare` is for **sorting**. Both stay Turkish whatever the
interface language — the data is Turkish.

## tools/check_swift.py

A pre-compile scan with seven rules. Each one was born from a real bug in this
project and proven by reintroducing it:

1. Call to an undefined member (a helper dropped during a file rewrite)
2. Missing argument label — understands trailing closures
3. Key path into a tuple (`ForEach(x.enumerated(), id: \.offset)`)
4. Chained leading dot in a generic `ShapeStyle` position
5. A local `let` inside a `ForEach` closure
6. A synthetic `Binding` on a presentation modifier — the setter wipes the
   state the completion handler is about to read
7. `DateFormatter`'s symbol arrays are `[String]?`, not `[String]!`

Run it before you build: `python3 tools/check_swift.py`.

It exists because the app was largely written without a Swift compiler to hand.
If you have Xcode, it is a cheap extra pass rather than a necessity — but rules
1, 2 and 6 catch things the compiler reports confusingly or not at all.

## Releases

`.github/workflows/release.yml` builds the app, packages a DMG and attaches it
to a GitHub release when a `v*` tag is pushed:

```
git tag v1.0
git push origin v1.0
```

The DMG is unsigned, so users go through Gatekeeper's "Open Anyway" once; the
release notes say so. Signing and notarising it needs a paid Apple Developer
Program membership — put the certificate in repository secrets and add
`codesign`, `notarytool` and `stapler` steps to that same file. Nothing else
changes.

## On the list

- **An editable timetable** — move `LessonSlot.all` out of code and into
  Settings. Everything downstream already reads through it, so it is close to a
  one-point change; the catch is that the week grid assumes nine periods when
  it sizes its rows, and `SlotPicker`'s grid is a hardcoded nine columns.
- **Fast topic entry in the week grid** — double-click a block, type, Tab to
  the next period.
- **An app icon** — needs an asset catalog in the Resources build phase (see
  point 4 above).
