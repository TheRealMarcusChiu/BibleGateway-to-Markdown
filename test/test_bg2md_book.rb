require 'minitest/autorun'
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
