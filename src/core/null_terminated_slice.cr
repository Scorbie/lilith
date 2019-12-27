struct NullTerminatedSlice
  getter size

  def initialize(@buffer : UInt8*)
    @size = 0
    until @buffer[@size] == 0
      @size += 1
    end
  end

  def [](idx : Int)
    abort "NullTerminatedSlice: out of range" if idx > @size || idx < 0
    @buffer[idx]
  end

  def [](range : Range(Int, Int))
    abort "NullTerminatedSlice: out of range" if range.begin > range.end
    Slice(UInt8).new(@buffer + range.begin, range.size)
  end

  def each(&block)
    i = 0
    while i < @size
      yield @buffer[i]
      i += 1
    end
  end

  def to_unsafe
    @buffer
  end

  def to_s(io)
    each do |ch|
      io.print ch.unsafe_chr
    end
  end
end
