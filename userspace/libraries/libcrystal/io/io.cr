abstract class IO
  abstract def read(slice : Bytes)
  abstract def write(slice : Bytes)

  def <<(obj) : self
    obj.to_s self
    self
  end

  def puts : Nil
    self << '\n'
  end

  def puts(obj) : Nil
    self << obj
    puts
  end

  def puts(*objects : _) : Nil
    objects.each do |obj|
      puts obj
    end
    nil
  end

  def print(*objects : _) : Nil
    objects.each do |obj|
      self << obj
    end
    nil
  end

  def gets_to_end
    buffer = uninitialized UInt8[512]
    builder = String::Builder.new
    while (nread = read(buffer.to_slice)) > 0
      builder << buffer[0, nread]
    end
    builder.to_s
  end
end
