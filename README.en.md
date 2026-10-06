# MED

*[Türkçe sürüm / Turkish version](README.md)*

A lecture archive for medical school, for macOS. Native SwiftUI, single user,
no account, no server, no subscription.

It answers one question fast: **what was that lesson about, and where are its
slides?**

## What it does

- **Sessions** — one record per lesson: the day's topic, its course, instructor,
  committee, tags and notes.
- **The school timetable, built in** — nine 40-minute periods; one tap sets the
  real times. A lesson that runs across several periods reads as one block.
- **Theory / Lab / Exam**, with labs and exams badged so they stand out.
- **Calendar** — month grid, an Apple-Calendar-style week grid coloured by
  course, and a single day read as a timetable.
- **Topics taught across two periods** fold into one row, numbered (1/2), and
  share their files: the break in the middle does not hand out a second
  handout.
- **Search and filter** over the whole archive — course, instructor, committee,
  type, and "topics with no slides yet".
- **Files** — link the PDFs you already have, preview them with QuickLook,
  reveal them in Finder. The app never copies, moves or renames a file; it
  remembers where it is.
- **Folder scan** — point it at a folder and it works out which session each
  file belongs to, from the date in the file name, the folder it sits in and
  how close its topic is. Three confidence groups, tick what you want applied.
- **Past papers** per committee, each with a year and a language.
- **JSON export** of the whole archive, for reading and for carrying the data
  elsewhere.
- **Turkish and English**, switched in Settings, no relaunch.

## Install

### From a release

Download `MED.dmg` from the [releases page](../../releases), open it and drag
**MED** to your Applications folder.

The app is distributed **unsigned**, so on first launch macOS will say the
developer could not be verified. Open **System Settings → Privacy & Security**,
find the line about MED near the bottom and press **Open Anyway**. You do this
once.

(Signing the app so that it opens with a double-click requires a paid Apple
Developer Program membership. The source is all here instead.)

### From source

Requires macOS 14 or later and Xcode 15 or later. No Apple Developer account
is needed.

```
git clone https://github.com/turkeer/med-archive.git
cd med-archive
open MED.xcodeproj
```

Then press ⌘R.

## How your files are treated

The app stores **where** a file is, never a copy of it. It never copies, moves,
renames or deletes anything on disk. Removing a file from a session forgets
where that file was and leaves the file alone.

Pick a root folder in Settings (⌘,) and files under it are stored relative to
it, so moving or renaming that folder does not break the links. A file you move
somewhere else leaves its record pointing at nothing — the **File tools** menu
on the Topics screen lists every such record and lets you point it at the
file's new location.

The App Sandbox is deliberately off: this is not going to the App Store, so a
plain path is all that is needed and the whole security-scoped-bookmark layer
disappears.

## Data

Everything lives in one SwiftData store on your Mac. Settings (⌘,) shows where
it is and opens it in Finder — that file is the backup worth copying. The JSON
export is for reading and for moving data elsewhere; it does not restore.

## Adapting it to your school

The timetable is nine 40-minute periods because that is one school's day. It is
defined in code, in `MED/Support/LessonSlot.swift`, and sessions store their
**real** start and end times rather than a period number — so editing that
table migrates nothing. Existing records keep the times they had and simply
stop lining up with a period, which the app shows as a custom time.

Making the timetable editable from Settings is the obvious next step and is
noted as such; the one thing to watch is that the week grid currently assumes
nine periods when it sizes its rows.

## Notes for anyone reading the code

The Turkish README is the long one: it documents every architectural decision
and the pitfalls behind them, including the SwiftData trap that costs you an
afternoon (a newly added non-optional `Codable` enum attribute crashes on the
first existing row, because SwiftData does not backfill it).

Two things worth knowing before you add a file:

- `MED.xcodeproj/project.pbxproj` is hand-written. Use
  `tools/add_to_xcodeproj.py <path>` to register a new source file — it needs
  four entries, not one.
- `tools/check_swift.py` is a pre-compile scan with seven rules, each one born
  from a real bug in this project and proven by reintroducing it.

## Licence

MIT — see [LICENSE](LICENSE). Use it, change it, ship it.

Made by Türker Akın & Claude.
