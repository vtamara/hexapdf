# -*- encoding: utf-8 -*-

require 'test_helper'
require 'hexapdf/document'
require 'hexapdf/composer'
require 'stringio'

describe HexaPDF::Composer do
  before do
    @composer = HexaPDF::Composer.new
  end

  describe "initialize" do
    it "creates a composer object with default values" do
      assert_kind_of(HexaPDF::Document, @composer.document)
      assert_kind_of(HexaPDF::Type::Page, @composer.page)
      assert_equal(36, @composer.frame.left)
      assert_equal(36, @composer.frame.bottom)
      assert_equal(523, @composer.frame.width)
      assert_equal(770, @composer.frame.height)
      assert_kind_of(HexaPDF::Layout::Style, @composer.style(:base))
    end

    it "allows the customization of the page size" do
      composer = HexaPDF::Composer.new(page_size: [0, 0, 100, 100])
      assert_equal([0, 0, 100, 100], composer.page.box.value)
    end

    it "allows the customization of the page orientation" do
      composer = HexaPDF::Composer.new(page_orientation: :landscape)
      assert_equal([0, 0, 842, 595], composer.page.box.value)
    end

    it "allows the customization of the margin" do
      composer = HexaPDF::Composer.new(margin: [100, 80, 60, 40])
      assert_equal(40, composer.frame.left)
      assert_equal(60, composer.frame.bottom)
      assert_equal(475, composer.frame.width)
      assert_equal(682, composer.frame.height)
    end

    it "yields itself" do
      yielded = nil
      composer = HexaPDF::Composer.new {|c| yielded = c }
      assert_same(composer, yielded)
    end
  end

  describe "::create" do
    it "creates, yields, and writes a document" do
      io = StringIO.new
      HexaPDF::Composer.create(io, &:new_page)
      io.rewind
      assert_equal(2, HexaPDF::Document.new(io: io).pages.count)
    end
  end

  describe "new_page" do
    it "creates a new page with the stored information" do
      c = HexaPDF::Composer.new(page_size: [0, 0, 50, 100], margin: 10)
      c.new_page
      assert_equal([0, 0, 50, 100], c.page.box.value)
      assert_equal(10, c.frame.left)
      assert_equal(10, c.frame.bottom)
    end

    it "uses the provided information for the new and all following pages" do
      @composer.new_page(page_size: [0, 0, 50, 100], margin: 10)
      assert_equal([0, 0, 50, 100], @composer.page.box.value)
      assert_equal(10, @composer.frame.left)
      assert_equal(10, @composer.frame.bottom)
      @composer.new_page
      assert_same(@composer.document.pages[2], @composer.page)
      assert_equal([0, 0, 50, 100], @composer.page.box.value)
      assert_equal(10, @composer.frame.left)
      assert_equal(10, @composer.frame.bottom)
    end
  end

  it "returns the current x-position" do
    assert_equal(36, @composer.x)
  end

  it "returns the current y-position" do
    assert_equal(806, @composer.y)
  end

  describe "style" do
    it "delegates to layout.style" do
      @composer.document.layout.style(:base, font_size: 20)
      assert_equal(20, @composer.style(:base).font_size)
      @composer.style(:base, font_size: 30)
      assert_equal(30, @composer.document.layout.style(:base).font_size)
    end
  end

  describe "text/formatted_text/image/box" do
    before do
      test_self = self
      @composer.define_singleton_method(:draw_box) do |arg|
        test_self.instance_variable_set(:@box, arg)
      end
    end

    it "delegates #text to layout.text" do
      @composer.text("Test", width: 10, height: 15, style: {font_size: 20},
                     box_style: {font_size: 30}, line_spacing: 2)
      assert_equal(10, @box.width)
      assert_equal(15, @box.height)
      assert_equal(30, @box.style.font_size)
      items = @box.instance_variable_get(:@items)
      assert_equal(1, items.length)
      assert_same(20, items.first.style.font_size)
    end

    it "delegates #formatted_text to layout.formatted_text" do
      @composer.formatted_text(["Test"], width: 10, height: 15)
      assert_equal(10, @box.width)
      assert_equal(15, @box.height)
      assert_equal(1, @box.instance_variable_get(:@items).length)
    end

    it "delegates #image to layout.image" do
      form = @composer.document.add({Type: :XObject, Subtype: :Form, BBox: [0, 0, 10, 10]})
      @composer.image(form, width: 10)
      assert_equal(10, @box.width)
      assert_equal(0, @box.height)
    end

    it "delegates #box to layout.box" do
      image = @composer.document.images.add(File.join(TEST_DATA_DIR, 'images', 'gray.jpg'))
      @composer.box(:list, width: 20) {|list| list.image(image) }
      assert_equal(20, @box.width)
      assert_same(image, @box.children[0].image)
    end
  end

  describe "draw_box" do
    def create_box(**kwargs)
      HexaPDF::Layout::Box.new(**kwargs) {}
    end

    it "draws the box if it completely fits" do
      @composer.draw_box(create_box(height: 100))
      @composer.draw_box(create_box)
      assert_operators(@composer.canvas.contents,
                       [[:save_graphics_state],
                        [:concatenate_matrix, [1, 0, 0, 1, 36, 706]],
                        [:restore_graphics_state],
                        [:save_graphics_state],
                        [:concatenate_matrix, [1, 0, 0, 1, 36, 36]],
                        [:restore_graphics_state]])
    end

    it "draws the box on a new page if the frame is already full" do
      first_page_canvas = @composer.canvas
      @composer.draw_box(create_box)
      @composer.draw_box(create_box)
      refute_same(first_page_canvas, @composer.canvas)
      assert_operators(@composer.canvas.contents,
                       [[:save_graphics_state],
                        [:concatenate_matrix, [1, 0, 0, 1, 36, 36]],
                        [:restore_graphics_state]])
    end

    it "splits the box across two pages" do
      first_page_contents = @composer.canvas.contents
      @composer.draw_box(create_box(height: 400))

      box = create_box(height: 400)
      box.define_singleton_method(:split) do |*|
        [box, HexaPDF::Layout::Box.new(height: 100) {}]
      end
      @composer.draw_box(box)
      assert_operators(first_page_contents,
                       [[:save_graphics_state],
                        [:concatenate_matrix, [1, 0, 0, 1, 36, 406]],
                        [:restore_graphics_state],
                        [:save_graphics_state],
                        [:concatenate_matrix, [1, 0, 0, 1, 36, 6]],
                        [:restore_graphics_state]])
      assert_operators(@composer.canvas.contents,
                       [[:save_graphics_state],
                        [:concatenate_matrix, [1, 0, 0, 1, 36, 706]],
                        [:restore_graphics_state]])
    end

    it "finds a new region if splitting didn't work" do
      first_page_contents = @composer.canvas.contents
      @composer.draw_box(create_box(height: 400))
      @composer.draw_box(create_box(height: 100, width: 300, style: {position: :float}))

      box = create_box(width: 400, height: 400)
      @composer.draw_box(box)
      assert_operators(first_page_contents,
                       [[:save_graphics_state],
                        [:concatenate_matrix, [1, 0, 0, 1, 36, 406]],
                        [:restore_graphics_state],
                        [:save_graphics_state],
                        [:concatenate_matrix, [1, 0, 0, 1, 36, 306]],
                        [:restore_graphics_state]])
      assert_operators(@composer.canvas.contents,
                       [[:save_graphics_state],
                        [:concatenate_matrix, [1, 0, 0, 1, 36, 406]],
                        [:restore_graphics_state]])
    end

    it "raises an error if a box doesn't fit onto an empty page" do
      assert_raises(HexaPDF::Error) do
        @composer.draw_box(create_box(height: 800))
      end
    end
  end

  describe "create_stamp" do
    it "creates and returns a form XObject" do
      stamp = @composer.create_stamp(10, 5)
      assert_kind_of(HexaPDF::Type::Form, stamp)
      assert_equal(10, stamp.width)
      assert_equal(5, stamp.height)
    end

    it "allows using a block to draw on the canvas of the form XObject" do
      stamp = @composer.create_stamp(10, 10) do |canvas|
        canvas.line_width(5)
      end
      assert_equal("5 w\n", stamp.canvas.contents)
    end
  end
end
