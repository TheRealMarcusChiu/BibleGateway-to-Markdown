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
