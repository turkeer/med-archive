# MED

*[Türkçe / Turkish](README.md)*

A lecture archive for medical school. A macOS app — no account, no server, no
subscription, no ads. Everything stays on your Mac.

It answers one question fast: **what was that lesson about, and where are its
slides?**

## What it does

- **Sessions** — one record per lesson: the day's topic, its course, instructor,
  committee, tags and notes.
- **The school timetable, built in** — nine 40-minute periods. One tap sets the
  times instead of two clock pickers. A topic running across two periods shows
  as a single block.
- **Theory / Lab / Exam** — labs and exams are badged so they stand out.
- **Calendar** — month grid, an Apple-Calendar-style week view coloured by
  course, and a day read as a timetable.
- **Two lessons on one topic** fold into a single row, numbered (1/2), and
  **share their files**: the break in the middle does not hand out a second
  handout.
- **Search and filter** — course, instructor, committee, type, and **"topics
  with no slides yet"**.
- **Files** — link the PDFs you already have, preview with the space bar, reveal
  in Finder.
- **Folder scan** — point it at a folder and it works out which session each
  file belongs to, from the date in the file name, the folder, and how close the
  topic is. Sorted into certain / weak / no match; you tick what gets applied.
- **Past papers** per committee, with a year and a language.
- **Turkish and English** — switched in Settings, no relaunch.

## Install

Download `MED.dmg` from the [releases page](../../releases), open it and drag
**MED** to your Applications folder.

On first launch macOS will say **the developer could not be verified**. That is
expected: the app is distributed unsigned, and all of its source is here for
anyone to read. To open it:

1. Open **System Settings → Privacy & Security**
2. Scroll down and find the line about MED
3. Press **Open Anyway**

You do this once. After that it opens like any other app.

## What happens to your files

**Nothing.** The app remembers *where* a file is; it does not keep a copy. It
never copies, moves, renames or deletes anything. Removing a file from a session
means forgetting where that file was — the file stays put.

Pick a **root folder** in Settings (⌘,) and files under it are stored relative
to it, so moving or renaming that folder does not break the links.

A file you move elsewhere leaves its record pointing at nothing. The **File
tools** menu on the Topics screen lists every such record and lets you show it
the file's new location.

## Where your data lives

In one file, on your Mac. Settings (⌘,) shows where it is and opens it in
Finder — **that is the file worth backing up.** Keeping it in an iCloud folder
or letting Time Machine have it is enough.

The File menu (⌘⇧E) exports the whole archive as readable JSON: for checking
what is there and for carrying the data elsewhere.

## Adapting it to your school

The timetable is currently in code: nine 40-minute periods starting at 08:50.
If your school differs, the table in `MED/Support/LessonSlot.swift` is the
place to change for now — making it editable from Settings is on the list.

The good news: sessions store their **real** start and end times rather than a
period number, so changing that table breaks no existing record.

## Reading the code / contributing

The architectural decisions, the SwiftData pitfalls and the reasoning behind
every choice are in [docs/DEVELOPMENT.md](docs/DEVELOPMENT.md).

## Licence

MIT — see [LICENSE](LICENSE). Use it, change it, ship it.

Made by Türker Akın & Claude.
