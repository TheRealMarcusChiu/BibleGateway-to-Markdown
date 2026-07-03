#!/usr/bin/env ruby
#------------------------------------------------------------------------------
# Bulk book downloader for bg2md.rb
# Downloads every verse of a Bible book as individual markdown files:
#   ./VERSION/BOOK/CHAPTER/BOOK-CHAPTER-VERSE.md
# Spec: docs/superpowers/specs/2026-07-03-bulk-verse-download-design.md
#------------------------------------------------------------------------------
VERSION = '1.0.0'.freeze unless defined?(VERSION)

require 'optparse'
require 'open3'
require 'fileutils'
require 'rbconfig'

module BG2MDBook
  # 66 books: canonical abbreviation (used in paths and BibleGateway lookups)
  # => chapter count. Chapter counts are the same across versions; verse
  # counts are not, so those are discovered at runtime.
  BOOKS = {
    'Gen' => 50, 'Exod' => 40, 'Lev' => 27, 'Num' => 36, 'Deut' => 34,
    'Josh' => 24, 'Judg' => 21, 'Ruth' => 4, '1Sam' => 31, '2Sam' => 24,
    '1Kgs' => 22, '2Kgs' => 25, '1Chr' => 29, '2Chr' => 36, 'Ezra' => 10,
    'Neh' => 13, 'Esth' => 10, 'Job' => 42, 'Ps' => 150, 'Prov' => 31,
    'Eccl' => 12, 'Song' => 8, 'Isa' => 66, 'Jer' => 52, 'Lam' => 5,
    'Ezek' => 48, 'Dan' => 12, 'Hos' => 14, 'Joel' => 3, 'Amos' => 9,
    'Obad' => 1, 'Jonah' => 4, 'Mic' => 7, 'Nah' => 3, 'Hab' => 3,
    'Zeph' => 3, 'Hag' => 2, 'Zech' => 14, 'Mal' => 4,
    'Matt' => 28, 'Mark' => 16, 'Luke' => 24, 'John' => 21, 'Acts' => 28,
    'Rom' => 16, '1Cor' => 16, '2Cor' => 13, 'Gal' => 6, 'Eph' => 6,
    'Phil' => 4, 'Col' => 4, '1Thess' => 5, '2Thess' => 3, '1Tim' => 6,
    '2Tim' => 4, 'Titus' => 3, 'Phlm' => 1, 'Heb' => 13, 'Jas' => 5,
    '1Pet' => 5, '2Pet' => 3, '1John' => 5, '2John' => 1, '3John' => 1,
    'Jude' => 1, 'Rev' => 22
  }.freeze

  # Common BibleGateway version codes shown in --help. Any BibleGateway
  # abbreviation is accepted; an unknown one just fails on the first fetch.
  COMMON_VERSIONS = %w[NIV NIVUK ESV NET NLT KJV NKJV NASB MSG AMP CSB].freeze

  BG2MD_SCRIPT = File.join(__dir__, 'bg2md.rb')

  module_function

  # Case-insensitive lookup; returns the canonical abbreviation or nil.
  def find_book(name)
    BOOKS.keys.find { |k| k.casecmp?(name.to_s) }
  end

  def verse_path(version, book, chapter, verse)
    File.join(version, book, chapter.to_s, "#{book}-#{chapter}-#{verse}.md")
  end

  # bg2md.rb exits 0 even on failure, so sniff the output instead: good
  # output starts with the '# <ref> (<version>)' heading (after a blank line).
  def valid_output?(text)
    !text.nil? && text.lstrip.start_with?('# ')
  end

  # Find the highest verse number in a whole-chapter bg2md output.
  # Verse numbers appear as inline 'N ' tokens; a chapter start appears as
  # 'C:1 ' (the verse part is what counts). The heading line is skipped.
  def parse_max_verse(markdown)
    text = markdown.to_s.sub(/^# .*$/, '')
    verses = []
    text = text.gsub(/(\d+):(\d+)\s/) do
      verses << Regexp.last_match(2).to_i
      ' '
    end
    text.scan(/(?:\A|\s)(\d+)\s/) { |m| verses << m[0].to_i }
    verses.max
  end

  def bg2md_cmd(args)
    [RbConfig.ruby, BG2MD_SCRIPT, *args]
  end

  # Whole-chapter fetch used only to count verses: numbering ON, all
  # extras (copyright, headers, footnotes, crossrefs) OFF.
  def fetch_chapter(version, book, chapter, runner)
    runner.call(bg2md_cmd(['-c', '-e', '-f', '-r', '-v', version, "#{book} #{chapter}"]))
  end

  # Per-verse fetch: crossrefs kept; copyright, headers, footnotes and
  # verse numbers OFF (the filename already encodes the verse).
  def fetch_verse(version, book, chapter, verse, runner)
    runner.call(bg2md_cmd(['-c', '-e', '-f', '-n', '-v', version, "#{book} #{chapter}:#{verse}"]))
  end

  def default_runner
    lambda do |cmd|
      stdout, _status = Open3.capture2(*cmd)
      stdout
    end
  end

  # Download every verse of `book` (canonical abbrev) into
  # ./VERSION/Book/ch/Book-ch-v.md under the current directory.
  # Returns { written:, skipped:, failed: [refs] }.
  def download_book(version:, book:, delay: 1.0, runner: default_runner,
                    sleeper: ->(s) { sleep(s) }, out: $stdout)
    stats = { written: 0, skipped: 0, failed: [] }
    (1..BOOKS.fetch(book)).each do |ch|
      chapter_md = fetch_chapter(version, book, ch, runner)
      sleeper.call(delay)
      max_verse = valid_output?(chapter_md) ? parse_max_verse(chapter_md) : nil
      if max_verse.nil?
        stats[:failed] << "#{book} #{ch} (whole chapter)"
        out.puts "FAILED: #{book} #{ch} -- could not fetch chapter to count verses"
        next
      end
      out.puts "#{book} #{ch}: #{max_verse} verses"
      (1..max_verse).each do |v|
        path = verse_path(version, book, ch, v)
        if File.file?(path) && !File.zero?(path)
          stats[:skipped] += 1
          next
        end
        verse_md = fetch_verse(version, book, ch, v, runner)
        sleeper.call(delay)
        if valid_output?(verse_md)
          FileUtils.mkdir_p(File.dirname(path))
          File.write(path, verse_md.lstrip)
          stats[:written] += 1
        else
          stats[:failed] << "#{book} #{ch}:#{v}"
          out.puts "FAILED: #{book} #{ch}:#{v}"
        end
      end
    end
    stats
  end
end

if $PROGRAM_NAME == __FILE__
  options = { delay: 1.0 }
  parser = OptionParser.new do |o|
    o.banner = 'Usage: bg2md_book.rb [options] VERSION BOOK'
    o.separator ''
    o.separator '  Downloads every verse of BOOK as individual markdown files:'
    o.separator '  ./VERSION/BOOK/CHAPTER/BOOK-CHAPTER-VERSE.md'
    o.separator ''
    o.separator 'Options:'
    o.on('--delay SECONDS', Float, 'Pause between requests (default: 1)') do |d|
      options[:delay] = d
    end
    o.on('-h', '--help', 'Show this help') do
      puts o
      puts
      puts 'BOOK values (chapter count in brackets):'
      BG2MDBook::BOOKS.each_slice(6) do |row|
        puts '  ' + row.map { |b, c| format('%-12s', "#{b}(#{c})") }.join
      end
      puts
      puts 'VERSION values (common ones; any BibleGateway abbreviation works):'
      puts '  ' + BG2MDBook::COMMON_VERSIONS.join(', ')
      exit
    end
  end
  parser.parse!

  if ARGV.length != 2
    warn 'Error: need exactly two arguments: VERSION BOOK (see --help)'
    exit 1
  end
  version = ARGV[0]
  book = BG2MDBook.find_book(ARGV[1])
  if book.nil?
    warn "Error: unknown book '#{ARGV[1]}'. Run with --help to list books."
    exit 1
  end

  stats = BG2MDBook.download_book(version: version, book: book, delay: options[:delay])
  puts
  puts "Done: #{stats[:written]} written, #{stats[:skipped]} skipped (already existed), #{stats[:failed].size} failed."
  unless stats[:failed].empty?
    puts 'Failed references (rerun the same command to retry):'
    stats[:failed].each { |r| puts "  #{r}" }
    exit 1
  end
end
