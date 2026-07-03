#!/usr/bin/env ruby
#------------------------------------------------------------------------------
# Post-download crossref wikilinker for bg2md_book.rb output.
# Mirrors ./VERSION/ into ./VERSION-wikilinked/, turning the references in
# each file's '### Crossrefs' section into [[Book-ch-v|original text]]
# wikilinks (Obsidian style). Source files are never modified.
#
# Usage: ruby wikilink_crossrefs.rb VERSION      e.g. ruby wikilink_crossrefs.rb NIV
#------------------------------------------------------------------------------
require 'fileutils'
require 'stringio'

module WikilinkCrossrefs
  # BibleGateway crossref abbreviations (and our canonical names) => the
  # canonical folder/file abbreviation used by bg2md_book.rb.
  ALIASES = {
    'Ge' => 'Gen', 'Gen' => 'Gen', 'Ex' => 'Exod', 'Exod' => 'Exod',
    'Lev' => 'Lev', 'Nu' => 'Num', 'Num' => 'Num', 'Dt' => 'Deut',
    'Deut' => 'Deut', 'Jos' => 'Josh', 'Josh' => 'Josh', 'Jdg' => 'Judg',
    'Judg' => 'Judg', 'Ru' => 'Ruth', 'Ruth' => 'Ruth',
    '1Sa' => '1Sam', '1Sam' => '1Sam', '2Sa' => '2Sam', '2Sam' => '2Sam',
    '1Ki' => '1Kgs', '1Kgs' => '1Kgs', '2Ki' => '2Kgs', '2Kgs' => '2Kgs',
    '1Ch' => '1Chr', '1Chr' => '1Chr', '2Ch' => '2Chr', '2Chr' => '2Chr',
    'Ezr' => 'Ezra', 'Ezra' => 'Ezra', 'Ne' => 'Neh', 'Neh' => 'Neh',
    'Est' => 'Esth', 'Esth' => 'Esth', 'Job' => 'Job',
    'Ps' => 'Ps', 'Psa' => 'Ps', 'Pr' => 'Prov', 'Prov' => 'Prov',
    'Ecc' => 'Eccl', 'Eccl' => 'Eccl', 'SS' => 'Song', 'Song' => 'Song',
    'Isa' => 'Isa', 'Jer' => 'Jer', 'La' => 'Lam', 'Lam' => 'Lam',
    'Eze' => 'Ezek', 'Ezek' => 'Ezek', 'Da' => 'Dan', 'Dan' => 'Dan',
    'Hos' => 'Hos', 'Joel' => 'Joel', 'Am' => 'Amos', 'Amos' => 'Amos',
    'Ob' => 'Obad', 'Obad' => 'Obad', 'Jnh' => 'Jonah', 'Jonah' => 'Jonah',
    'Mic' => 'Mic', 'Na' => 'Nah', 'Nah' => 'Nah', 'Hab' => 'Hab',
    'Zep' => 'Zeph', 'Zeph' => 'Zeph', 'Hag' => 'Hag',
    'Zec' => 'Zech', 'Zech' => 'Zech', 'Mal' => 'Mal',
    'Mt' => 'Matt', 'Matt' => 'Matt', 'Mk' => 'Mark', 'Mark' => 'Mark',
    'Lk' => 'Luke', 'Luke' => 'Luke', 'Jn' => 'John', 'John' => 'John',
    'Ac' => 'Acts', 'Acts' => 'Acts', 'Ro' => 'Rom', 'Rom' => 'Rom',
    '1Co' => '1Cor', '1Cor' => '1Cor', '2Co' => '2Cor', '2Cor' => '2Cor',
    'Gal' => 'Gal', 'Eph' => 'Eph', 'Php' => 'Phil', 'Phil' => 'Phil',
    'Col' => 'Col', '1Th' => '1Thess', '1Thess' => '1Thess',
    '2Th' => '2Thess', '2Thess' => '2Thess', '1Ti' => '1Tim', '1Tim' => '1Tim',
    '2Ti' => '2Tim', '2Tim' => '2Tim', 'Tit' => 'Titus', 'Titus' => 'Titus',
    'Phm' => 'Phlm', 'Phlm' => 'Phlm', 'Heb' => 'Heb', 'Jas' => 'Jas',
    '1Pe' => '1Pet', '1Pet' => '1Pet', '2Pe' => '2Pet', '2Pet' => '2Pet',
    '1Jn' => '1John', '1John' => '1John', '2Jn' => '2John', '2John' => '2John',
    '3Jn' => '3John', '3John' => '3John', 'Jude' => 'Jude', 'Rev' => 'Rev'
  }.freeze

  # Books where a bare 'Book N' reference means verse N, not chapter N.
  SINGLE_CHAPTER = %w[Obad Phlm 2John 3John Jude].freeze

  # 'ver 15' / 'S ver 15' -- a verse in the file's own chapter.
  VER_RE = /\A(S\s+)?ver\s+(\d+)(?:[-–]\d+)?(?:pp)?\z/.freeze
  # '[S ]Book? [C:]V[-[C:]V][pp|Ref]' -- everything else. Link goes to the
  # first verse of a range; the whole original text becomes the display alias.
  REF_RE = /\A(S\s+)?((?:[123]\s?)?[A-Z][A-Za-z]*\s+)?(?:(\d+):)?(\d+)(?:[-–](?:\d+:)?\d+)?(?:pp|Ref)?\z/.freeze

  module_function

  # Turn one reference segment (between ;/,/em-dash separators) into a
  # wikilink, updating ctx's book/chapter memory. Unparseable segments are
  # returned untouched.
  def link_segment(seg, ctx)
    lead = seg[/\A\s*/]
    trail = seg[/\s*\z/]
    core = seg.strip
    return seg if core.empty?

    if (m = core.match(VER_RE))
      target = "#{ctx[:file_book]}-#{ctx[:file_chapter]}-#{m[2]}"
    elsif (m = core.match(REF_RE))
      if m[2]
        book = ALIASES[m[2].strip.delete(' ')]
        return seg if book.nil? # not a book we know: leave untouched

        ctx[:book] = book
      end
      if m[3] # C:V
        ctx[:chapter] = m[3].to_i
        verse = m[4].to_i
      elsif m[2] # 'Book N': verse for single-chapter books, else chapter N
        if SINGLE_CHAPTER.include?(ctx[:book])
          ctx[:chapter] = 1
          verse = m[4].to_i
        else
          ctx[:chapter] = m[4].to_i
          verse = 1
        end
      else # bare 'N': verse in the current chapter
        verse = m[4].to_i
      end
      target = "#{ctx[:book]}-#{ctx[:chapter]}-#{verse}"
    else
      return seg
    end

    display = core.sub(/\AS\s+/, '')
    prefix = m[1] ? 'S ' : ''
    "#{lead}#{prefix}[[#{target}|#{display}]]#{trail}"
  end

  # Transform one '[^X]: refs' crossref line. file_book/file_chapter come
  # from the filename and seed the reference context.
  def transform_crossref_line(line, file_book, file_chapter)
    m = line.match(/\A(\[\^[^\]]+\]:\s*)(.*)\z/)
    return line unless m

    ctx = { book: file_book, chapter: file_chapter,
            file_book: file_book, file_chapter: file_chapter }
    parts = m[2].split(/([;,]\s*|\s+—\s+)/)
    transformed = parts.map do |part|
      part =~ /\A([;,]\s*|\s+—\s+)\z/ ? part : link_segment(part, ctx)
    end
    m[1] + transformed.join
  end

  # Rewrite only the lines inside the '### Crossrefs' section.
  def transform_content(content, file_book, file_chapter)
    in_crossrefs = false
    content.lines.map do |line|
      if line.start_with?('### ')
        in_crossrefs = line.strip == '### Crossrefs'
        line
      elsif in_crossrefs
        eol = line.end_with?("\n") ? "\n" : ''
        transform_crossref_line(line.chomp, file_book, file_chapter) + eol
      else
        line
      end
    end.join
  end

  # Mirror ./VERSION/**/*.md into ./VERSION-wikilinked/, transforming
  # crossrefs. Returns the number of files written.
  def mirror_version(version, out: $stdout)
    dest_root = "#{version}-wikilinked"
    files = Dir.glob(File.join(version, '**', '*.md')).sort
    files.each do |path|
      base = File.basename(path, '.md')
      content = File.read(path, encoding: 'utf-8')
      if (m = base.match(/\A(.+)-(\d+)-\d+\z/))
        content = transform_content(content, m[1], m[2].to_i)
      end
      target = File.join(dest_root, path.split(File::SEPARATOR)[1..-1].join(File::SEPARATOR))
      FileUtils.mkdir_p(File.dirname(target))
      File.write(target, content)
    end
    out.puts "Wrote #{files.size} files to #{dest_root}/"
    files.size
  end
end

if $PROGRAM_NAME == __FILE__
  version = ARGV[0]
  if version.nil? || version.start_with?('-')
    puts 'Usage: ruby wikilink_crossrefs.rb VERSION'
    puts
    puts 'Mirrors ./VERSION/ (bg2md_book.rb output) into ./VERSION-wikilinked/,'
    puts 'converting the references under each file\'s "### Crossrefs" heading'
    puts 'into [[Book-ch-v|original text]] wikilinks. ./VERSION/ is not modified.'
    exit(version.nil? ? 1 : 0)
  end
  unless Dir.exist?(version)
    warn "Error: no directory ./#{version} here. Run bg2md_book.rb first."
    exit 1
  end
  WikilinkCrossrefs.mirror_version(version)
end
