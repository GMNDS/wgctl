module Wgctl
  module TUI
    enum Key
      Up
      Down
      Left
      Right
      Enter
      Escape
      Backspace
      Char
    end

    struct KeyEvent
      property key : Key
      property char : Char?

      def initialize(@key : Key, @char : Char? = nil)
      end
    end

    class Terminal
      def self.enter_alternate_screen
        print "\e[?1049h\e[H\e[?25l"
        STDOUT.flush
      end

      def self.exit_alternate_screen
        print "\e[?1049l\e[?25h"
        STDOUT.flush
      end

      def self.clear_screen
        print "\e[2J\e[H"
        STDOUT.flush
      end

      def self.hide_cursor
        print "\e[?25l"
        STDOUT.flush
      end

      def self.show_cursor
        print "\e[?25h"
        STDOUT.flush
      end

      def self.move_cursor(row : Int32, col : Int32)
        print "\e[#{row};#{col}H"
        STDOUT.flush
      end

      # Reads a single key event in raw mode
      def self.read_key(io : IO) : KeyEvent
        c = io.read_char
        return KeyEvent.new(Key::Escape) if c.nil?

        case c
        when '\r', '\n'
          KeyEvent.new(Key::Enter)
        when '\u007f', '\b'
          KeyEvent.new(Key::Backspace)
        when '\e'
          # Check for ANSI escape sequences
          # If no immediate character is waiting or peek is nil, treat as Escape key
          begin
            if io.responds_to?(:read_byte)
              # Read next with small timeout / non-blocking check
              next_char = io.read_char
              if next_char == '['
                code = io.read_char
                case code
                when 'A' then return KeyEvent.new(Key::Up)
                when 'B' then return KeyEvent.new(Key::Down)
                when 'C' then return KeyEvent.new(Key::Right)
                when 'D' then return KeyEvent.new(Key::Left)
                end
              end
            end
          rescue
          end
          KeyEvent.new(Key::Escape)
        else
          KeyEvent.new(Key::Char, c)
        end
      end
    end
  end
end
