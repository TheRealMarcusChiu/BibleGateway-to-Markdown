require 'minitest/autorun'
require 'tmpdir'
require 'fileutils'
require_relative '../wikilink_crossrefs'

class TestTransformCrossrefLine < Minitest::Test
  def t(line, book: 'Luke', chapter: 23)
    WikilinkCrossrefs.transform_crossref_line(line, book, chapter)
  end

  def test_simple_book_refs
    assert_equal '[^E]: [[Matt-27-1|Mt 27:1]]; [[Mark-15-1|Mk 15:1]]',
                 t('[^E]: Mt 27:1; Mk 15:1')
  end

  def test_see_marker_stays_outside_link
    assert_equal '[^D]: S [[Matt-5-22|Mt 5:22]]', t('[^D]: S Mt 5:22')
  end

  def test_parallel_passage_line_with_em_dash
    assert_equal '[^A]: [[Luke-22-67|22:67-71pp]] — [[Matt-26-63|Mt 26:63-66]]; ' \
                 '[[Mark-14-61|Mk 14:61-63]]; [[John-18-19|Jn 18:19-21]]',
                 t('[^A]: 22:67-71pp — Mt 26:63-66; Mk 14:61-63; Jn 18:19-21')
  end

  def test_comma_verse_inherits_chapter
    assert_equal '[^B]: [[Luke-23-2|23:2]], [[Luke-23-3|3pp]] — [[Matt-27-11|Mt 27:11-14]]',
                 t('[^B]: 23:2, 3pp — Mt 27:11-14')
  end

  def test_cross_chapter_en_dash_range_links_first_verse
    assert_equal '[^C]: [[John-18-39|Jn 18:39–19:16]]', t('[^C]: Jn 18:39–19:16')
  end

  def test_book_context_flows_across_semicolons
    line = '[^A]: 1Ch 21:1; Job 1:6-9; Lk 10:18; 13:16; 22:3, 31; 2Co 2:11; 11:14'
    expected = '[^A]: [[1Chr-21-1|1Ch 21:1]]; [[Job-1-6|Job 1:6-9]]; [[Luke-10-18|Lk 10:18]]; ' \
               '[[Luke-13-16|13:16]]; [[Luke-22-3|22:3]], [[Luke-22-31|31]]; ' \
               '[[2Cor-2-11|2Co 2:11]]; [[2Cor-11-14|11:14]]'
    assert_equal expected, t(line, book: 'Matt', chapter: 4)
  end

  def test_ver_refs_use_own_book_and_chapter
    assert_equal '[^D]: S [[John-3-15|ver 15]]', t('[^D]: S ver 15', book: 'John', chapter: 3)
    assert_equal '[^E]: [[John-3-36|ver 36]]; [[John-6-29|Jn 6:29]], [[John-6-40|40]]',
                 t('[^E]: ver 36; Jn 6:29, 40', book: 'John', chapter: 3)
  end

  def test_single_chapter_book_number_is_a_verse
    assert_equal '[^A]: [[Jude-1-14|Jude 14]]', t('[^A]: Jude 14')
  end

  def test_chapter_only_ref_links_verse_one
    assert_equal '[^A]: [[Ps-119-1|Ps 119]]', t('[^A]: Ps 119')
  end

  def test_ref_suffix_variant
    assert_equal '[^B]: [[Luke-9-13|9:13-17Ref]] — [[2Kgs-4-42|2Ki 4:42-44]]',
                 t('[^B]: 9:13-17Ref — 2Ki 4:42-44', book: 'Luke', chapter: 9)
  end

  def test_unrecognized_segment_left_alone
    assert_equal '[^A]: some junk; [[Matt-5-22|Mt 5:22]]', t('[^A]: some junk; Mt 5:22')
  end

  def test_non_crossref_line_untouched
    assert_equal 'plain text 22:67 here', t('plain text 22:67 here')
  end
end

class TestTransformContent < Minitest::Test
  CONTENT = <<~MD
    # Luke 22:67 (New International Version)
    "If you are the Messiah," they said, "tell us."[^A]

    ### Footnotes
    [^a]: Mt 1:1 some footnote text, not a crossref

    ### Crossrefs
    [^A]: S Mt 5:22
  MD

  def test_only_crossrefs_section_transformed
    result = WikilinkCrossrefs.transform_content(CONTENT, 'Luke', 22)
    assert_includes result, '[^A]: S [[Matt-5-22|Mt 5:22]]'
    assert_includes result, '[^a]: Mt 1:1 some footnote text, not a crossref'
    assert_includes result, '"tell us."[^A]'
  end
end

class TestMirrorVersion < Minitest::Test
  def test_mirrors_into_wikilinked_dir_leaving_source_untouched
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('TST/Luke/22')
        src = "# Luke 22:67 (X)\ntext[^A]\n\n### Crossrefs\n[^A]: Mt 26:63-66\n"
        File.write('TST/Luke/22/Luke-22-67.md', src)
        count = WikilinkCrossrefs.mirror_version('TST', out: StringIO.new)
        assert_equal 1, count
        mirrored = File.read('TST-wikilinked/Luke/Luke_22/Luke-22-67.md')
        assert_includes mirrored, '[^A]: [[Matt-26-63|Mt 26:63-66]]'
        assert_equal src, File.read('TST/Luke/22/Luke-22-67.md')
      end
    end
  end

  def test_chapter_dirs_renamed_with_book_prefix
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('TST/Gen/2')
        File.write('TST/Gen/2/Gen-2-1.md', "# Genesis 2:1 (X)\ntext\n")
        WikilinkCrossrefs.mirror_version('TST', out: StringIO.new)
        assert File.file?('TST-wikilinked/Gen/Gen_2/Gen-2-1.md')
        refute Dir.exist?('TST-wikilinked/Gen/2')
      end
    end
  end

  def test_book_and_chapter_notes_created
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('TST/Gen/1')
        File.write('TST/Gen/1/Gen-1-1.md', "# Genesis 1:1 (X)\ntext\n")
        WikilinkCrossrefs.mirror_version('TST', out: StringIO.new)

        book_note = File.read('TST-wikilinked/Gen.md')
        assert book_note.start_with?("# Genesis\n"), 'book note starts with full book name'
        assert book_note.split("\n").size >= 3, 'book note has a description'

        chapter_note = File.read('TST-wikilinked/Gen/Gen_1.md')
        assert chapter_note.start_with?("# Genesis 1\n"), 'chapter note starts with book title + chapter'
        assert_includes chapter_note, book_note.lines.last.strip, 'chapter note carries the book description'
      end
    end
  end

  def test_book_info_covers_all_66_books
    require_relative '../bg2md_book'
    assert_equal BG2MDBook::BOOKS.keys.sort, WikilinkCrossrefs::BOOK_INFO.keys.sort
    WikilinkCrossrefs::BOOK_INFO.each do |abbrev, (name, desc)|
      refute_nil name, "#{abbrev} has a full name"
      assert desc.is_a?(String) && !desc.strip.empty?, "#{abbrev} has a description"
    end
  end
end
