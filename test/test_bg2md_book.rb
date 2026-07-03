require 'minitest/autorun'
require 'tmpdir'
require 'stringio'
require_relative '../bg2md_book'

class TestBookTable < Minitest::Test
  def test_has_66_books
    assert_equal 66, BG2MDBook::BOOKS.size
  end

  def test_known_chapter_counts
    assert_equal 50, BG2MDBook::BOOKS['Gen']
    assert_equal 6, BG2MDBook::BOOKS['Eph']
    assert_equal 150, BG2MDBook::BOOKS['Ps']
    assert_equal 1, BG2MDBook::BOOKS['Jude']
    assert_equal 22, BG2MDBook::BOOKS['Rev']
  end

  def test_find_book_case_insensitive
    assert_equal 'Gen', BG2MDBook.find_book('gen')
    assert_equal 'Eph', BG2MDBook.find_book('EPH')
    assert_equal '1Cor', BG2MDBook.find_book('1cor')
    assert_nil BG2MDBook.find_book('Nope')
  end
end

class TestPathsAndValidation < Minitest::Test
  def test_verse_path
    assert_equal 'NIV/Eph/1/Eph-1-1.md', BG2MDBook.verse_path('NIV', 'Eph', 1, 1)
    assert_equal 'ESV/Ps/119/Ps-119-176.md', BG2MDBook.verse_path('ESV', 'Ps', 119, 176)
  end

  def test_valid_output
    assert BG2MDBook.valid_output?("\n# John 3:16 (New International Version)\ntext")
    refute BG2MDBook.valid_output?('')
    refute BG2MDBook.valid_output?(nil)
    refute BG2MDBook.valid_output?("Error: could not find useful data\n")
  end
end

class TestParseMaxVerse < Minitest::Test
  def test_simple_chapter
    md = "\n# Ephesians 1 (New International Version)\n1:1 Paul, an apostle text 2 Grace and peace text 3 Praise be"
    assert_equal 3, BG2MDBook.parse_max_verse(md)
  end

  def test_heading_number_ignored
    md = "\n# Psalm 150 (New International Version)\n150:1 Praise the LORD. text 2 Praise him text 6 Let everything"
    assert_equal 6, BG2MDBook.parse_max_verse(md)
  end

  def test_no_verses
    assert_nil BG2MDBook.parse_max_verse("\n# Something (X)\nno digits here")
  end

  def test_leaked_publisher_line_ignored
    # bg2md leaks this publisher line into the passage even with -c; its
    # year must not be read as a verse number (regression: Jude -> 2019).
    md = "\n# Jude (New International Version)\n1:1 Jude, a servant text 2 mercy text 25 now and forevermore \n" \
         'NIV Reverse Interlinear Bible: English to Hebrew and English to Greek. Copyright © 2019 by Zondervan.'
    assert_equal 25, BG2MDBook.parse_max_verse(md)
  end

  def test_implausibly_large_numbers_ignored
    md = "\n# X (Y)\n1:1 text 2 text 1996 stray big number"
    assert_equal 2, BG2MDBook.parse_max_verse(md)
  end
end

class TestStripLeakedCopyright < Minitest::Test
  def test_removes_publisher_line
    md = "# Jude 25 (New International Version)\nto the only God be glory.\n" \
         "NIV Reverse Interlinear Bible: English to Hebrew and English to Greek. Copyright © 2019 by Zondervan.\n\n" \
         "### Crossrefs\n[^A]: Jn 5:44\n"
    expected = "# Jude 25 (New International Version)\nto the only God be glory.\n\n### Crossrefs\n[^A]: Jn 5:44\n"
    assert_equal expected, BG2MDBook.strip_leaked_copyright(md)
  end

  def test_leaves_clean_output_alone
    md = "# Jude 25 (X)\ntext\n"
    assert_equal md, BG2MDBook.strip_leaked_copyright(md)
  end
end

class TestFetchers < Minitest::Test
  def test_bg2md_cmd_points_at_sibling_script
    cmd = BG2MDBook.bg2md_cmd(['-v', 'NIV', 'Gen 1'])
    assert_equal RbConfig.ruby, cmd[0]
    assert cmd[1].end_with?('bg2md.rb')
    assert_equal ['-v', 'NIV', 'Gen 1'], cmd[2..-1]
  end

  def test_fetch_chapter_flags_keep_numbering_drop_crossrefs
    captured = nil
    runner = ->(cmd) { captured = cmd; 'out' }
    assert_equal 'out', BG2MDBook.fetch_chapter('NIV', 'Gen', 2, runner)
    assert_equal ['-c', '-e', '-f', '-r', '-v', 'NIV', 'Gen 2'], captured[2..-1]
  end

  def test_fetch_verse_flags_keep_crossrefs_drop_numbering
    captured = nil
    runner = ->(cmd) { captured = cmd; 'out' }
    assert_equal 'out', BG2MDBook.fetch_verse('NIV', 'Gen', 2, 7, runner)
    assert_equal ['-c', '-e', '-f', '-n', '-v', 'NIV', 'Gen 2:7'], captured[2..-1]
  end
end

class TestDownloadBook < Minitest::Test
  CHAPTER_MD = "\n# Jude 1 (Test)\n1:1 Jude, a servant text 2 Mercy, peace text 3 Dear friends"
  VERSE_MD = "\n# Jude 1:1 (Test)\nJude, a servant of Jesus Christ\n"

  def fake_runner(fail_refs = [])
    lambda do |cmd|
      ref = cmd.last
      return "Error: nope\n" if fail_refs.include?(ref)
      ref.include?(':') ? VERSE_MD.sub('1:1', ref.split(' ').last) : CHAPTER_MD
    end
  end

  def run_download(runner)
    BG2MDBook.download_book(version: 'TST', book: 'Jude', delay: 0,
                            runner: runner, sleeper: ->(_s) {}, out: StringIO.new)
  end

  def test_writes_one_file_per_verse
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        stats = run_download(fake_runner)
        assert_equal 3, stats[:written]
        assert_equal 0, stats[:skipped]
        assert_empty stats[:failed]
        assert File.file?('TST/Jude/1/Jude-1-1.md')
        assert File.file?('TST/Jude/1/Jude-1-3.md')
        content = File.read('TST/Jude/1/Jude-1-2.md')
        assert content.start_with?('# Jude 1:2 (Test)')
      end
    end
  end

  def test_skips_existing_nonempty_files
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        FileUtils.mkdir_p('TST/Jude/1')
        File.write('TST/Jude/1/Jude-1-2.md', 'already here')
        stats = run_download(fake_runner)
        assert_equal 2, stats[:written]
        assert_equal 1, stats[:skipped]
        assert_equal 'already here', File.read('TST/Jude/1/Jude-1-2.md')
      end
    end
  end

  def test_failed_verse_recorded_and_not_written
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        stats = run_download(fake_runner(['Jude 1:2']))
        assert_equal 2, stats[:written]
        assert_equal ['Jude 1:2'], stats[:failed]
        refute File.exist?('TST/Jude/1/Jude-1-2.md')
      end
    end
  end

  def test_failed_chapter_fetch_recorded
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) do
        stats = run_download(fake_runner(['Jude 1']))
        assert_equal 0, stats[:written]
        assert_equal ['Jude 1 (whole chapter)'], stats[:failed]
      end
    end
  end
end
