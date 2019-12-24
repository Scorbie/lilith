GC_ARRAY_HEADER_TYPE = 0xFFFF_FFFF.to_usize
GC_ARRAY_HEADER_SIZE = sizeof(USize) * 2

class Array(T)
  @capacity : Int32
  getter capacity

  def size
    return 0 if @capacity == 0
    @buffer[1].to_i32
  end

  protected def size=(new_size)
    return if @capacity == 0
    @buffer[1] = new_size.to_usize
  end

  private def malloc_size(new_size)
    new_size.to_usize * sizeof(T) + GC_ARRAY_HEADER_SIZE
  end

  private def capacity_for_ptr(ptr)
    ((Allocator.block_size_for_ptr(ptr) - GC_ARRAY_HEADER_SIZE) // sizeof(T)).to_i32
  end

  private def new_buffer(new_capacity)
    if size > new_capacity
      panic "size must be smaller than capacity"
    elsif new_capacity <= @capacity
      return
    end
    if @buffer.null?
      {% if T < Int %}
        @buffer = Gc.unsafe_malloc(malloc_size(new_capacity), true).as(USize*)
      {% else %}
        @buffer = Gc.unsafe_malloc(malloc_size(new_capacity)).as(USize*)
      {% end %}
      @buffer[0] = GC_ARRAY_HEADER_TYPE
      @buffer[1] = 0u32
    else
      @buffer = Gc.realloc(@buffer.as(Void*), malloc_size(new_capacity)).as(USize*)
    end
    @capacity = capacity_for_ptr @buffer
  end

  def initialize
    @capacity = 0
    @buffer = Pointer(USize).null
  end

  def initialize(initial_capacity : Int32)
    if initial_capacity > 0
      {% if T < Int %}
        @buffer = Gc.unsafe_malloc(malloc_size(initial_capacity), true).as(USize*)
      {% else %}
        @buffer = Gc.unsafe_malloc(malloc_size(initial_capacity)).as(USize*)
      {% end %}
      @capacity = capacity_for_ptr(@buffer)
      @buffer[0] = GC_ARRAY_HEADER_TYPE
      @buffer[1] = 0u32
    else
      @buffer = Pointer(USize).null
      @capacity = 0
    end
  end

  def clone
    Array(T).build(size) do |buffer|
      size.times do |i|
        buffer[i] = to_unsafe[i]
      end
      size
    end
  end

  def self.build(capacity : Int) : self
    ary = Array(T).new(capacity)
    ary.size = (yield ary.to_unsafe).to_i
    ary
  end

  def self.new(size : Int, &block : Int32 -> T)
    Array(T).build(size) do |buffer|
      size.to_i.times do |i|
        buffer[i] = yield i
      end
      size
    end
  end

  def to_unsafe
    (@buffer + 2).as(T*)
  end

  def [](idx : Int)
    panic "accessing out of bounds!" unless 0 <= idx < size
    to_unsafe[idx]
  end

  def []?(idx : Int) : T?
    return nil unless 0 <= idx && idx < size
    to_unsafe[idx]
  end

  def []=(idx : Int, value : T)
    panic "accessing out of bounds!" unless 0 <= idx < size
    to_unsafe[idx] = value
  end

  def push(value : T)
    if size < @capacity
      to_unsafe[size] = value
    else
      new_buffer(size + 1)
      to_unsafe[size] = value
    end
    self.size = size + 1
  end

  def each
    i = 0
    while i < size
      yield to_unsafe[i]
      i += 1
    end
  end

  def reverse_each
    i = size - 1
    while i >= 0
      yield to_unsafe[i]
      i -= 1
    end
  end
end
