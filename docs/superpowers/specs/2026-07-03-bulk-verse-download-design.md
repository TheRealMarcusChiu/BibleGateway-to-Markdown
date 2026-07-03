# Bulk Verse Download Script (`bg2md_book.rb`) — Design

Date: 2026-07-03
Status: Approved

## Purpose

Download every verse of a given Bible book from BibleGateway (via the existing
`bg2md.rb`) as individual markdown files, organised as:

```
./BIBLE_VERSION/BOOK_NAME/CHAPTER_NUMBER/BOOK_NAME-CHAPTER_NUMBER-VERSE_NUMBER.md
```

Example: `./NIV/Eph/1/Eph-1-1.md`

## CLI

```
ruby bg2md_book.rb [options] VERSION BOOK
```

- `VERSION` — BibleGateway version abbreviation, e.g. `NIV`, `ESV`.
- `BOOK` — book abbreviation, e.g. `Gen`, `Eph`.
- `--help` — usage, plus the full list of 66 book abbreviations (with chapter
  counts) and a list of common version codes (NIV, NIVUK, ESV, NET, NLT, KJV,
  NKJV, NASB, MSG, AMP, CSB), noting any BibleGateway abbreviation is accepted.
- `--delay SECONDS` — pause between requests (default 1).

Book matching is case-insensitive against the canonical abbreviation table;
unknown books/versions produce a clear error (books validated locally,
versions validated by the first fetch failing).

## Behaviour

1. Look up the book in a hardcoded 66-book table: canonical abbreviation
   (used in paths/filenames) + chapter count.
2. For each chapter:
   a. Fetch the whole chapter via `bg2md.rb -c -e -f -r -v VERSION "<Book> <ch>"`
      (numbering kept ON) and parse the highest verse number from the output
      to learn the verse count. Verse counts are NOT hardcoded because they
      vary between versions.
   b. For each verse 1..N, call
      `bg2md.rb -c -e -f -n -v VERSION "<Book> <ch>:<v>"`
      and write stdout to `./VERSION/Book/ch/Book-ch-v.md`.
3. Flags chosen (user decisions): keep cross-references; exclude copyright
   (`-c`), editorial headers (`-e`), footnotes (`-f`), and verse numbers
   (`-n`); no bold words of Jesus.
4. Sleep `--delay` seconds between every bg2md invocation.

## Resumability

Before fetching a verse, skip it if its target file already exists and is
non-empty. A killed run can simply be rerun.

## Error handling

- `bg2md.rb` exits 0 even on failure, so validate output instead: a good
  result starts with a `# <reference> (<version>)` heading line. On failure,
  do not write the file; record the reference.
- Print a summary at the end: files written, skipped (already existed), and
  a list of failed references (rerun to retry them).
- If the chapter fetch used for verse-counting fails, report and skip that
  chapter (its verses are listed as failed).

## Non-goals

- No parallel fetching (politeness to BibleGateway).
- No support for versions with range verse-numbering (e.g. MSG `5-8`);
  single-verse lookups there are untested.
- No changes to `bg2md.rb` itself.
- Clipboard side-effect of bg2md is tolerated (last verse ends up on the
  clipboard).

## Testing

- Verse-count parsing and path construction covered by running against a
  small book/chapter (e.g. Jude, 3 John) live, plus `bg2md.rb -t` test-file
  mode if HTML fixtures are available.
- Manual acceptance: `ruby bg2md_book.rb NIV Eph` produces
  `./NIV/Eph/1..6/Eph-*-*.md` with crossrefs and no copyright/footnotes.
