module Wgctl
  module Output
    class Table
      property headers : Array(String)
      property rows : Array(Array(String))

      def initialize(@headers : Array(String))
        @rows = [] of Array(String)
      end

      def add_row(row : Array(String))
        @rows << row
      end

      def render : String
        return "" if @headers.empty?

        # Calculate max width for each column
        col_widths = @headers.map(&.size)

        @rows.each do |row|
          row.each_with_index do |cell, idx|
            if idx < col_widths.size
              col_widths[idx] = Math.max(col_widths[idx], cell.size)
            end
          end
        end

        io = IO::Memory.new

        # Render header
        header_line = @headers.map_with_index do |h, idx|
          if idx == @headers.size - 1
            h
          else
            h.ljust(col_widths[idx] + 3)
          end
        end.join.rstrip
        io.puts header_line

        # Render rows
        @rows.each do |row|
          line = row.map_with_index do |cell, idx|
            if idx == @headers.size - 1
              cell
            else
              cell.ljust(col_widths[idx] + 3)
            end
          end.join.rstrip
          io.puts line
        end

        io.to_s
      end
    end
  end
end
