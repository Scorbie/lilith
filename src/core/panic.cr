def abort(*args)
  # TODO: print call stack
  Serial.print *args
  Pointer(Int32).null.value = 0
  while true
  end
end

def raise(*args)
end

{% if flag?(:release) && false %}
  macro breakpoint
  end
{% else %}
  @[NoInline]
  fun breakpoint
    asm("nop")
  end
{% end %}
