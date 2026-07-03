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

  # Full name and a one-line description for every book, used for the
  # book/chapter folder notes written into the mirror.
  BOOK_INFO = {
    'Gen' => ['Genesis', "Creation, the fall, the flood, and the patriarchs Abraham, Isaac, Jacob, and Joseph -- the beginnings of God's covenant people."],
    'Exod' => ['Exodus', "Israel's deliverance from slavery in Egypt under Moses, the giving of the Law at Sinai, and the building of the tabernacle."],
    'Lev' => ['Leviticus', "Laws on sacrifices, priesthood, purity, and holiness for Israel's worship of God."],
    'Num' => ['Numbers', "Israel's forty years of wilderness wandering between Sinai and the edge of the promised land."],
    'Deut' => ['Deuteronomy', "Moses' farewell speeches restating the Law and urging Israel to love and obey God as they enter the promised land."],
    'Josh' => ['Joshua', 'The conquest of Canaan and the division of the land among the twelve tribes under Joshua.'],
    'Judg' => ['Judges', "Israel's repeated cycle of sin, oppression, and deliverance through judges such as Deborah, Gideon, and Samson."],
    'Ruth' => ['Ruth', "A Moabite widow's loyalty to her mother-in-law Naomi and her redemption by Boaz, ancestor of David."],
    '1Sam' => ['1 Samuel', "The prophet Samuel, Israel's first king Saul, and the rise of David."],
    '2Sam' => ['2 Samuel', "David's reign as king of Israel, his sin with Bathsheba, and its consequences for his house."],
    '1Kgs' => ['1 Kings', "Solomon's reign and temple, the division of the kingdom, and the prophet Elijah."],
    '2Kgs' => ['2 Kings', 'The kings of divided Israel and Judah down to the fall of Samaria and the exile to Babylon, with the ministry of Elisha.'],
    '1Chr' => ['1 Chronicles', "Genealogies of Israel and a priestly retelling of David's reign."],
    '2Chr' => ['2 Chronicles', "Solomon and the kings of Judah retold, from the temple's building to its destruction and the decree of return."],
    'Ezra' => ['Ezra', "The return of the exiles to Jerusalem, the rebuilding of the temple, and Ezra's reforms."],
    'Neh' => ['Nehemiah', "The rebuilding of Jerusalem's walls under Nehemiah and the renewal of the covenant."],
    'Esth' => ['Esther', 'A Jewish queen in Persia who risks her life to save her people from destruction.'],
    'Job' => ['Job', 'A righteous sufferer wrestles with God over the meaning of his affliction.'],
    'Ps' => ['Psalms', "Israel's songbook -- 150 psalms of praise, lament, thanksgiving, and trust."],
    'Prov' => ['Proverbs', 'Wise sayings on living skillfully in the fear of the LORD.'],
    'Eccl' => ['Ecclesiastes', "The Teacher's search for meaning \"under the sun\" and his conclusion to fear God."],
    'Song' => ['Song of Songs', 'A poetic celebration of love between bride and bridegroom.'],
    'Isa' => ['Isaiah', 'Judgment and hope: the Holy One of Israel, the coming Messiah, and the servant who suffers for his people.'],
    'Jer' => ['Jeremiah', 'The weeping prophet warns Judah of the Babylonian exile and promises a new covenant.'],
    'Lam' => ['Lamentations', 'Five laments over the destruction of Jerusalem.'],
    'Ezek' => ['Ezekiel', 'Visions from exile in Babylon -- judgment on Jerusalem, and promised restoration with a new heart and spirit.'],
    'Dan' => ['Daniel', "Faithful Jews in the Babylonian court and apocalyptic visions of God's kingdom over the empires."],
    'Hos' => ['Hosea', "The prophet's marriage to unfaithful Gomer pictures God's persistent love for wayward Israel."],
    'Joel' => ['Joel', "A locust plague heralds the day of the LORD and the promise of God's Spirit poured out."],
    'Amos' => ['Amos', "A shepherd prophet denounces Israel's injustice and empty religion."],
    'Obad' => ['Obadiah', "Judgment on Edom for gloating over Jerusalem's fall."],
    'Jonah' => ['Jonah', "A reluctant prophet, a great fish, and God's mercy on repentant Nineveh."],
    'Mic' => ['Micah', "Judgment on Israel and Judah's corruption, and the promised ruler from Bethlehem."],
    'Nah' => ['Nahum', 'The fall of Nineveh, capital of cruel Assyria.'],
    'Hab' => ['Habakkuk', "The prophet questions God's justice and learns that the righteous live by faith."],
    'Zeph' => ['Zephaniah', 'The sweeping day of the LORD and the joy of God rejoicing over his remnant.'],
    'Hag' => ['Haggai', "A call to rebuild the temple and put God's house first."],
    'Zech' => ['Zechariah', 'Night visions and promises of the coming king who arrives humble on a donkey.'],
    'Mal' => ["Malachi", "God's final Old Testament word -- a dispute with a complacent people and the promise of Elijah before the great day."],
    'Matt' => ['Matthew', "Jesus as Israel's Messiah -- his birth, the Sermon on the Mount, his death and resurrection, fulfilling the Scriptures."],
    'Mark' => ['Mark', 'A fast-moving account of Jesus the Son of God, the servant who gives his life as a ransom for many.'],
    'Luke' => ['Luke', 'A careful, orderly account of Jesus, friend of sinners and outcasts, written for Theophilus.'],
    'John' => ['John', 'The Word made flesh -- seven signs and "I am" sayings, written so that readers may believe and have life.'],
    'Acts' => ['Acts', 'The Spirit-empowered spread of the gospel from Jerusalem to Rome through Peter and Paul.'],
    'Rom' => ['Romans', "Paul's fullest exposition of the gospel -- righteousness from God by faith, for Jew and Gentile alike."],
    '1Cor' => ['1 Corinthians', 'Paul corrects a divided church on unity, purity, worship, spiritual gifts, love, and the resurrection.'],
    '2Cor' => ['2 Corinthians', 'Paul defends his ministry -- strength in weakness, treasure in jars of clay.'],
    'Gal' => ['Galatians', 'No other gospel: justification by faith apart from works of the law, and life by the Spirit.'],
    'Eph' => ['Ephesians', "God's cosmic plan in Christ -- saved by grace, one new humanity, armored for spiritual battle."],
    'Phil' => ['Philippians', 'A joyful letter from prison -- to live is Christ, and the mind of Christ who humbled himself.'],
    'Col' => ['Colossians', 'The supremacy of Christ over all powers, and life rooted in him.'],
    '1Thess' => ['1 Thessalonians', "Encouragement for a young church -- holy living and the hope of Christ's return."],
    '2Thess' => ['2 Thessalonians', 'Standing firm amid persecution and correcting alarm about the day of the Lord.'],
    '1Tim' => ['1 Timothy', 'Instructions to a young pastor in Ephesus on sound doctrine, church leaders, and godliness.'],
    '2Tim' => ['2 Timothy', "Paul's final letter -- guard the gospel, endure hardship, preach the word."],
    'Titus' => ['Titus', 'Ordering the churches of Crete with sound doctrine adorned by good works.'],
    'Phlm' => ['Philemon', 'A personal appeal to receive back the runaway slave Onesimus as a brother.'],
    'Heb' => ['Hebrews', 'Jesus the great high priest -- better than angels, Moses, and the old sacrifices; a call to persevering faith.'],
    'Jas' => ['James', 'Practical wisdom: faith that works, taming the tongue, and patience in trials.'],
    '1Pet' => ['1 Peter', "Hope for exiles -- standing firm in grace through suffering, following Christ's example."],
    '2Pet' => ['2 Peter', 'Growing in grace and guarding against false teachers while awaiting the day of the Lord.'],
    '1John' => ['1 John', 'Assurance for believers -- walking in the light, loving one another, believing in the Son.'],
    '2John' => ['2 John', 'Walking in truth and love, and refusing hospitality to deceivers.'],
    '3John' => ['3 John', "Commending Gaius's hospitality and rebuking domineering Diotrephes."],
    'Jude' => ['Jude', 'Contend for the faith against ungodly infiltrators.'],
    'Rev' => ['Revelation', "John's apocalypse -- letters to seven churches and visions of God's final victory and the new creation."]
  }.freeze

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

  # Transform one '[^X]: refs' crossref line into '- X: <wikilinked refs>'.
  # file_book/file_chapter come from the filename and seed the context.
  def transform_crossref_line(line, file_book, file_chapter)
    m = line.match(/\A\[\^([^\]]+)\]:\s*(.*)\z/)
    return line unless m

    ctx = { book: file_book, chapter: file_chapter,
            file_book: file_book, file_chapter: file_chapter }
    parts = m[2].split(/([;,]\s*|\s+—\s+)/)
    transformed = parts.map do |part|
      part =~ /\A([;,]\s*|\s+—\s+)\z/ ? part : link_segment(part, ctx)
    end
    "- #{m[1]}: " + transformed.join
  end

  # Before '### Crossrefs': [^X] markers become <sup>^X</sup>.
  # After it: each '[^X]: refs' line becomes a '- X:' bullet with wikilinks.
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
        line.gsub(/\[\^([^\]]+)\]/, '<sup>^\1</sup>')
      end
    end.join
  end

  # Mirror ./VERSION/**/*.md into ./VERSION-wikilinked/, transforming
  # crossrefs. Chapter folders are renamed Book/Book_N/ and folder notes
  # (Book.md beside each book folder, Book_N.md beside each chapter folder)
  # are added with the book name/chapter and description.
  # Returns the number of verse files written (folder notes not counted).
  def mirror_version(version, out: $stdout)
    dest_root = "#{version}-wikilinked"
    chapters_by_book = Hash.new { |h, k| h[k] = [] }
    files = Dir.glob(File.join(version, '**', '*.md')).sort
    files.each do |path|
      base = File.basename(path, '.md')
      content = File.read(path, encoding: 'utf-8')
      if (m = base.match(/\A(.+)-(\d+)-\d+\z/))
        content = transform_content(content, m[1], m[2].to_i)
      end
      rel = path.split(File::SEPARATOR)[1..-1]
      if rel.length == 3 # book/chapter/verse.md
        book, chapter, filename = rel
        chapters_by_book[book] << chapter
        target = File.join(dest_root, book, "#{book}_#{chapter}", filename)
      else
        target = File.join(dest_root, *rel)
      end
      FileUtils.mkdir_p(File.dirname(target))
      File.write(target, content)
    end
    notes = write_folder_notes(dest_root, chapters_by_book)
    out.puts "Wrote #{files.size} verse files and #{notes} folder notes to #{dest_root}/"
    files.size
  end

  # Book.md beside each book folder; Book_N.md beside each chapter folder.
  def write_folder_notes(dest_root, chapters_by_book)
    notes = 0
    chapters_by_book.each do |book, chapters|
      name, description = BOOK_INFO[book]
      next if name.nil? # unknown folder: mirror it, but no notes

      File.write(File.join(dest_root, "#{book}.md"), "# #{name}\n\n#{description}\n")
      notes += 1
      chapters.uniq.each do |chapter|
        File.write(File.join(dest_root, book, "#{book}_#{chapter}.md"),
                   "# #{name} #{chapter}\n\n#{description}\n")
        notes += 1
      end
    end
    notes
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
