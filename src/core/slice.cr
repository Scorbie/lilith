struct Slice(T)
  getter size

  def initialize(@buffer : Pointer(T), @size : Int32)
  end

  def self.null
    new Pointer(T).null, 0
  end

  def null?
    @buffer.null?
  end

  def self.malloc(sz)
    new Pointer(T).malloc(sz), sz
  end

  def self.malloc_atomic(sz)
    new Pointer(T).malloc_atomic(sz), sz
  end

  def self.mmalloc_a(sz, allocator)
    new allocator.malloc(sz * sizeof(T)).as(T*), sz
  end

  # manual malloc: this should only be used when the slice is
  # to be cleaned up before the function returns
  def self.mmalloc(sz)
    new Pointer(T).mmalloc(sz), sz
  end

  def mfree
    @buffer.mfree
    @buffer = Pointer(T).null
  end

  # FIXME: this must not be inlined or
  # memory corruption occurs (maybe related to gc)
  @[NoInline]
  def [](idx : Int)
    panic "Slice: out of range" if idx >= @size || idx < 0
    @buffer[idx]
  end

  @[NoInline]
  def []=(idx : Int, value : T)
    panic "Slice: out of range" if idx >= @size || idx < 0
    @buffer[idx] = value
  end

  def [](range : Range(Int, Int))
    panic "Slice: out of range" if range.begin > range.end
    Slice(T).new(@buffer + range.begin, range.size)
  end

  def to_unsafe
    @buffer
  end

  def each(&block)
    i = 0
    while i < @size
      yield @buffer[i]
      i += 1
    end
  end

  def ==(other : String)
    other == self
  end

  def to_s(io)
    io.print "Slice(", @buffer, " ", @size, ")"
  end
end
