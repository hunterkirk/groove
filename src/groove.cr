require "ncurses"

module Groove
  VERSION = "0.1.0"

  class Buffer
    getter lines : Array(String)
    property modified : Bool

    def initialize
      @lines = [""]
      @modified = false
    end

    def initialize(content : String)
      @lines = content.empty? ? [""] : content.split("\n", remove_empty: false)
      @modified = false
    end

    def line_count
      @lines.size
    end

    def char_count
      @lines.join("").size
    end

    def word_count
      @lines.join(" ").split.reject(&.empty?).size
    end

    def get_line(index : Int32) : String
      @lines[index]? || ""
    end

    def insert_char(line_idx : Int32, col_idx : Int32, char : Char) : Tuple(Int32, Int32)
      line = @lines[line_idx]
      before = line[0...col_idx]
      after = line[col_idx..]?
      @lines[line_idx] = before + char.to_s + (after || "")
      @modified = true
      {line_idx, col_idx + 1}
    end

    def insert_newline(line_idx : Int32, col_idx : Int32) : Tuple(Int32, Int32)
      line = @lines[line_idx]
      before = line[0...col_idx]
      after = line[col_idx..]?
      @lines.insert(line_idx + 1, after || "")
      @lines[line_idx] = before
      @modified = true
      {line_idx + 1, 0}
    end

    def delete_char(line_idx : Int32, col_idx : Int32) : Tuple(Int32, Int32)
      return {line_idx, col_idx} if line_idx >= @lines.size

      line = @lines[line_idx]
      if col_idx > 0
        before = line[0...col_idx - 1]
        after = line[col_idx..]?
        @lines[line_idx] = before + (after || "")
        @modified = true
        {line_idx, col_idx - 1}
      elsif line_idx > 0
        prev_line = @lines[line_idx - 1]
        new_col = prev_line.size
        @lines[line_idx - 1] = prev_line + line
        @lines.delete_at(line_idx)
        @modified = true
        {line_idx - 1, new_col}
      else
        {line_idx, col_idx}
      end
    end

    def delete_at_cursor(line_idx : Int32, col_idx : Int32) : Tuple(Int32, Int32)
      return {line_idx, col_idx} if line_idx >= @lines.size

      line = @lines[line_idx]
      if col_idx < line.size
        before = line[0...col_idx]
        after = line[col_idx + 1..]?
        @lines[line_idx] = before + (after || "")
        @modified = true
        {line_idx, col_idx}
      elsif line_idx < @lines.size - 1
        current_line = @lines[line_idx]
        next_line = @lines[line_idx + 1]
        @lines[line_idx] = current_line + next_line
        @lines.delete_at(line_idx + 1)
        @modified = true
        {line_idx, col_idx}
      else
        {line_idx, col_idx}
      end
    end

    def to_s
      @lines.join("\n")
    end
  end

  class Editor
    getter buffer : Buffer
    setter buffer : Buffer
    property cursor_line : Int32
    property cursor_col : Int32
    property filename : String?
    property menu_mode : Bool
    property current_menu_item : Int32

    property screen_height : Int32
    property screen_width : Int32
    property current_menu_item : Int32
    property wrap_width : Int32
    property margin_x : Int32
    property margin_y : Int32

    @scroll_offset : Int32
    @display_lines : Array(Tuple(Int32, String))

    def initialize
      @buffer = Buffer.new
      @cursor_line = 0
      @cursor_col = 0
      @filename = nil
      @menu_mode = false
      @current_menu_item = 0
      @screen_height = 0
      @screen_width = 0
      @wrap_width = 80
      @margin_x = 0
      @margin_y = 1
      @scroll_offset = 0
      @display_lines = [] of Tuple(Int32, String)
    end

    def initialize(filename : String)
      @buffer = Buffer.new(File.read(filename))
      @cursor_line = 0
      @cursor_col = 0
      @filename = filename
      @menu_mode = false
      @current_menu_item = 0
      @screen_height = 0
      @screen_width = 0
      @wrap_width = 80
      @margin_x = 0
      @margin_y = 1
      @scroll_offset = 0
      @display_lines = [] of Tuple(Int32, String)
    end

    def resize
      @screen_height = NCurses.lines - 2 - @margin_y
      @screen_width = NCurses.cols
      @margin_x = Math.max(0, (@screen_width - @wrap_width) // 2)
      compute_display_lines
      clamp_cursor
    end

    def compute_display_lines
      @display_lines.clear
      line_idx = 0
      @buffer.lines.each do |line|
        if line.size == 0
          @display_lines << {line_idx, ""}
        else
          pos = 0
          while pos < line.size
            remaining = line.size - pos
            if remaining <= @wrap_width
              chunk = line[pos..-1]
              @display_lines << {line_idx, chunk}
              break
            else
              break_point = pos + @wrap_width
              while break_point > pos && line[break_point - 1] != ' '
                break_point -= 1
              end
              if break_point == pos
                break_point = pos + @wrap_width
              end
              chunk = line[pos...break_point]
              @display_lines << {line_idx, chunk}
              pos = break_point
            end
          end
        end
        line_idx += 1
      end
      @display_lines << {line_idx, ""} if @display_lines.empty?
    end

    def cursor_to_display_pos : Tuple(Int32, Int32)
      cursor_line_text = @buffer.get_line(@cursor_line)
      col = @cursor_col
      
      display_idx = 0
      @display_lines.each do |d_line|
        src_line, text = d_line
        if src_line == @cursor_line
          if col <= text.size
            y = display_idx - @scroll_offset + @margin_y
            x = col + @margin_x
            return {y, x}
          end
          col -= text.size
        end
        display_idx += 1
      end
      
      {1 + @margin_y, @margin_x}
    end

    def clamp_cursor
      line = @buffer.get_line(@cursor_line)
      @cursor_col = Math.max(0, Math.min(@cursor_col, line.size))
      @cursor_line = Math.max(0, Math.min(@cursor_line, @buffer.line_count - 1))
      clamp_scroll
    end

    def clamp_scroll
      cursor_display_idx = 0
      char_count = 0
      @buffer.lines.each_with_index do |line, line_idx|
        if line_idx == @cursor_line
          @display_lines.each do |d_line|
            src_line, text = d_line
            if src_line == line_idx
              if char_count + text.size > @cursor_col
                break
              end
              char_count += text.size
            end
            cursor_display_idx += 1
          end
          break
        else
          line_len = line.size
          wrapped = line_len == 0 ? 1 : (line_len + @wrap_width - 1) / @wrap_width
          cursor_display_idx += wrapped
        end
      end

      if cursor_display_idx < @scroll_offset
        @scroll_offset = cursor_display_idx.to_i32
      elsif cursor_display_idx >= @scroll_offset + @screen_height
        @scroll_offset = (cursor_display_idx - @screen_height + 1).to_i32
      end
      @scroll_offset = Math.max(0, @scroll_offset)
    end

    def move_cursor_left
      if @cursor_col > 0
        @cursor_col -= 1
      elsif @cursor_line > 0
        @cursor_line -= 1
        @cursor_col = @buffer.get_line(@cursor_line).size
      end
      clamp_cursor
    end

    def move_cursor_right
      line = @buffer.get_line(@cursor_line)
      if @cursor_col < line.size
        @cursor_col += 1
      elsif @cursor_line < @buffer.line_count - 1
        @cursor_line += 1
        @cursor_col = 0
      end
      clamp_cursor
    end

    def move_cursor_up
      if @cursor_line > 0
        @cursor_line -= 1
      end
      line_len = @buffer.get_line(@cursor_line).size
      @cursor_col = Math.min(@cursor_col, line_len)
      clamp_cursor
    end

    def move_cursor_down
      if @cursor_line < @buffer.line_count - 1
        @cursor_line += 1
      end
      line_len = @buffer.get_line(@cursor_line).size
      @cursor_col = Math.min(@cursor_col, line_len)
      clamp_cursor
    end

    def move_to_line_start
      @cursor_col = 0
    end

    def move_to_line_end
      @cursor_col = @buffer.get_line(@cursor_line).size
    end

    def save : Bool
      return true if @filename.nil?

      begin
        File.write(@filename.as(String), @buffer.to_s)
        @buffer.modified = false
        true
      rescue
        false
      end
    end

    def save_as(name : String) : Bool
      begin
        File.write(name, @buffer.to_s)
        @filename = name
        @buffer.modified = false
        true
      rescue
        false
      end
    end

    def enter_menu_mode
      @menu_mode = true
      @current_menu_item = 0
    end

    def exit_menu_mode
      @menu_mode = false
    end

    def render
      NCurses.erase

      (0...@screen_height).each do |y|
        display_idx = y + @scroll_offset
        NCurses.move(y + @margin_y, @margin_x)
        if display_idx < @display_lines.size
          _line_idx, text = @display_lines[display_idx]
          NCurses.print(text)
          remaining = @wrap_width - text.size
          NCurses.print(" " * remaining) if remaining > 0
        else
          NCurses.print(" " * @wrap_width)
        end
      end

      NCurses.move(@screen_height + 1 + @margin_y, 0)
      NCurses.print(render_status.ljust(@screen_width))

      if @menu_mode
        render_menu
      else
        cursor_y, cursor_x = cursor_to_display_pos
        NCurses.move(cursor_y, cursor_x)
      end

      NCurses.refresh
    end

    private def render_status
      filename_display = @filename ? File.basename(@filename.as(String)) : "Untitled"
      words = @buffer.word_count
      chars = @buffer.char_count
      modified = @buffer.modified ? "*" : ""
      "#{filename_display}#{modified} | Wd: #{words} | Ch: #{chars}"
    end

    def render_menu
      NCurses.move(0, 0)
      NCurses.print(" " * @screen_width)

      menu_items = [
        "Open...",
        "Save",
        "Save As...",
        "Quit"
      ]

      menu_width = 30
      menu_start_x = (@screen_width - menu_width) // 2
      menu_start_y = @screen_height // 2 - menu_items.size // 2 + @margin_y

      menu_items.each_with_index do |item, idx|
        y = menu_start_y + idx
        NCurses.move(y, menu_start_x)
        prefix = idx == @current_menu_item ? "> " : "  "
        NCurses.print(prefix + item.ljust(menu_width - 2))
      end

      NCurses.move(@screen_height + 1 + @margin_y, 0)
      NCurses.print("Press ESC to exit menu, ENTER to select".ljust(@screen_width))
      NCurses.refresh
    end
  end

  MENU_ITEMS = ["Open...", "Save", "Save As...", "Quit"]

  def self.quick_save(editor : Editor)
    if editor.filename
      if editor.save
        show_message(editor, "Saved")
      else
        show_message(editor, "Error saving file")
      end
    else
      filename = prompt_filename(editor)
      if filename
        editor.save_as(filename)
        show_message(editor, "Saved as #{filename}")
      end
    end
  end

  def self.show_message(editor : Editor, msg : String)
    NCurses.move(editor.screen_height + 1 + editor.margin_y, 0)
    NCurses.print(msg.ljust(editor.screen_width))
    NCurses.refresh
    sleep 1.second
  end

  def self.run(filename : String? = nil)
    NCurses.start
    begin
      NCurses.cbreak
    rescue
    end
    NCurses.no_echo
    NCurses.keypad(true)
    NCurses.set_cursor(NCurses::Cursor::Visible)

    editor = filename ? Editor.new(filename) : Editor.new
    editor.resize

    last_save_time = Time.utc
    autosave_interval = 60

    loop do
      editor.render

      if editor.buffer.modified && editor.filename && (Time.utc - last_save_time).total_seconds >= autosave_interval
        editor.save
        last_save_time = Time.utc
      end

      key = NCurses.get_char

      if key.nil?
        next
      end

      if editor.menu_mode
        case key
        when NCurses::Key::Esc
          editor.exit_menu_mode
        when NCurses::Key::Up
          editor.current_menu_item = (editor.current_menu_item - 1) % MENU_ITEMS.size
        when NCurses::Key::Down
          editor.current_menu_item = (editor.current_menu_item + 1) % MENU_ITEMS.size
        when '\n'
          saved = handle_menu_selection(editor)
          last_save_time = Time.utc if saved
        end
      else
        case key
        when NCurses::Key::Esc
          editor.enter_menu_mode
        when 19
          quick_save(editor)
          last_save_time = Time.utc
        when 1
          editor.move_to_line_start
        when 5
          editor.move_to_line_end
        when NCurses::Key::Left
          editor.move_cursor_left
        when NCurses::Key::Right
          editor.move_cursor_right
        when NCurses::Key::Up
          editor.move_cursor_up
        when NCurses::Key::Down
          editor.move_cursor_down
        when NCurses::Key::Home
          editor.move_to_line_start
        when NCurses::Key::End
          editor.move_to_line_end
        when NCurses::Key::Backspace
          editor.cursor_line, editor.cursor_col = editor.buffer.delete_char(editor.cursor_line, editor.cursor_col)
        when NCurses::Key::Delete
          editor.cursor_line, editor.cursor_col = editor.buffer.delete_at_cursor(editor.cursor_line, editor.cursor_col)
        when '\n'
          editor.cursor_line, editor.cursor_col = editor.buffer.insert_newline(editor.cursor_line, editor.cursor_col)
        when Char
          if key >= ' ' && key <= '~'
            editor.cursor_line, editor.cursor_col = editor.buffer.insert_char(editor.cursor_line, editor.cursor_col, key)
          end
        end
      end

      editor.resize
    end

    NCurses.end
  end

  def self.handle_menu_selection(editor : Editor) : Bool
    result = false
    case editor.current_menu_item
    when 0
      filename = prompt_filename(editor)
      if filename && File.exists?(filename)
        editor.buffer = Buffer.new(File.read(filename))
        editor.filename = filename
      end
      editor.exit_menu_mode
    when 1
      if editor.filename
        editor.save
      else
        filename = prompt_filename(editor)
        editor.save_as(filename) if filename
      end
      editor.exit_menu_mode
      result = true
    when 2
      filename = prompt_filename(editor)
      if filename
        editor.save_as(filename)
        result = true
      end
      editor.exit_menu_mode
    when 3
      if editor.buffer.modified
        NCurses.move(editor.screen_height + 1, 0)
        NCurses.print("File modified. Press Y to quit without saving...".ljust(editor.screen_width))
        NCurses.refresh
        key = NCurses.get_char
        if key == 'y' || key == 'Y'
          NCurses.end
          exit
        end
      else
        NCurses.end
        exit
      end
    end
    result
  end

  def self.prompt_filename(editor : Editor) : String?
    NCurses.echo
    NCurses.move(editor.screen_height + 1 + editor.margin_y, 0)
    NCurses.print("Filename: ".ljust(editor.screen_width))
    NCurses.refresh

    filename = ""
    while (key = NCurses.get_char) != '\n'
      break if key == NCurses::Key::Esc
      if key == NCurses::Key::Backspace
        filename = filename[0...-1] if filename.size > 0
      elsif key.is_a?(Char) && key >= ' ' && key <= '~'
        filename += key.to_s
      end
      NCurses.move(editor.screen_height + 1 + editor.margin_y, 0)
      NCurses.print("Filename: #{filename}".ljust(editor.screen_width))
      NCurses.refresh
    end

    NCurses.no_echo
    filename.size > 0 ? filename : nil
  end
end

filename = ARGV[0]?
Groove.run(filename)
