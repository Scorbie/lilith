INTERRUPT_GATE      = 0x8Eu16
KERNEL_CODE_SEGMENT = 0x08u16

lib Kernel
  {% for i in 0..31 %}
    fun kcpuex{{ i.id }}
  {% end %}
  {% for i in 0..15 %}
    fun kirq{{ i.id }}
  {% end %}
end

module Idt
  extend self

  lib Data
    @[Packed]
    struct Idt
      limit : UInt16
      base : UInt64
    end

    @[Packed]
    struct IdtEntry
      offset_1 : UInt16 # offset bits 0..15
      selector : UInt16 # a code segment selector in GDT or LDT
      ist : UInt8
      type_attr : UInt8 # type and attributes
      offset_2 : UInt16 # offset bits 16..31
      offset_3 : UInt32 # offset bits 32..63
      zero : UInt32
    end

    struct Registers
      # Pushed by pushad:
      ds,
rbp, rdi, rsi,
r15, r14, r13, r12, r11, r10, r9, r8,
rdx, rcx, rbx, rax : UInt64
      # Interrupt number
      int_no : UInt64
      # Pushed by the processor automatically.
      rip, cs, rflags, userrsp, ss : UInt64
    end

    struct ExceptionRegisters
      # Pushed by pushad:
      ds,
rbp, rdi, rsi,
r15, r14, r13, r12, r11, r10, r9, r8,
rdx, rcx, rbx, rax : UInt64
      # Interrupt number
      int_no, errcode : UInt64
      # Pushed by the processor automatically.
      rip, cs, rflags, userrsp, ss : UInt64
    end
  end

  alias InterruptHandler = -> Nil

  # initialize
  IRQ_COUNT = 16
  @@irq_handlers = uninitialized InterruptHandler[IRQ_COUNT]

  # table init
  IDT_SIZE = 256
  @@idtr = uninitialized Data::Idt
  @@idt = uninitialized Data::IdtEntry[IDT_SIZE]

  def init_table
    @@idtr.limit = sizeof(Data::IdtEntry) * IDT_SIZE - 1
    @@idtr.base = @@idt.to_unsafe.address

    # cpu exception handlers
    {% if flag?(:release) && !flag?(:no_cpuex) %}
      {% for i in 0..31 %}
        init_idt_entry {{ i }}, KERNEL_CODE_SEGMENT,
          (->Kernel.kcpuex{{ i.id }}).pointer.address,
          INTERRUPT_GATE
      {% end %}
    {% end %}

    # hw interrupts
    {% for i in 0..15 %}
      init_idt_entry {{ i + 32 }}, KERNEL_CODE_SEGMENT,
        (->Kernel.kirq{{ i.id }}).pointer.address,
        INTERRUPT_GATE
    {% end %}

    asm("lidt ($0)" :: "r"(pointerof(@@idtr)) : "volatile")
  end

  def init_idt_entry(num : Int32, selector : UInt16, offset : UInt64, type : UInt16)
    idt = Data::IdtEntry.new
    idt.offset_1 = (offset & 0xFFFF)
    idt.ist = 1
    idt.selector = selector
    idt.type_attr = type
    idt.offset_2 = (offset >> 16) & 0xFFFF
    idt.offset_3 = (offset >> 32)
    idt.zero = 0
    @@idt[num] = idt
  end

  # handlers
  class_getter irq_handlers

  def register_irq(idx : Int, handler : InterruptHandler)
    @@irq_handlers[idx] = handler
  end

  # status
  @@status_mask = false
  class_getter status_mask

  {% if flag?(:record_cli) %}
    @@disabled_at = 0x0u64
    class_getter disabled_at
  {% end %}

  @[NoInline]
  def enable
    if !@@status_mask
      asm("sti" ::: "volatile")
    end
  end

  @[NoInline]
  def disable
    if !@@status_mask
      asm("cli" ::: "volatile")
    end
  end

  def disable(reenable = false, &block)
    if @@status_mask
      return yield
    end
    disable
    @@status_mask = true

    {% if flag?(:record_cli) %}
      asm("lea (%rip), $0" : "=r"(@@disabled_at) :: "volatile")
    {% end %}
    retval = yield

    @@status_mask = false
    enable if reenable
    retval
  end

  def check_if
    check = 0
    asm("pushfq; popq %rax" : "={rax}"(check) :: "volatile")
    panic "IF is set" if (check & 0x200) != 0
  end

  @@last_rsp = 0u64
  class_property last_rsp

  @@switch_processes = false
  class_property switch_processes
end

fun kirq_handler(frame : Idt::Data::Registers*)
  Idt.last_rsp = frame.value.userrsp
  PIC.eoi frame.value.int_no

  if Idt.irq_handlers[frame.value.int_no].pointer.null?
    Serial.print "no handler for ", frame.value.int_no, "\n"
  else
    Idt.disable do
      Idt.irq_handlers[frame.value.int_no].call
    end
  end

  if frame.value.int_no == 0 && Idt.switch_processes
    # preemptive multitasking...
    if (current_process = Multiprocessing::Scheduler.current_process)
      if current_process.sched_data.time_slice > 0
        # FIXME: context_switch_to_process must be called or cpu won't
        # have current process' context
        current_process.sched_data.time_slice -= 1
        Multiprocessing::Scheduler.context_switch_to_process(current_process)
        return
      end
    end
    Multiprocessing::Scheduler.switch_process(frame)
  end
end

EX_PAGEFAULT = 14

private def dump_frame(frame : Idt::Data::ExceptionRegisters*)
  {% for id in [
                 "ds",
                 "rbp", "rdi", "rsi",
                 "r15", "r14", "r13", "r12", "r11", "r10", "r9", "r8",
                 "rdx", "rcx", "rbx", "rax",
                 "int_no", "errcode",
                 "rip", "cs", "rflags", "userrsp", "ss",
               ] %}
    Serial.print {{ id }}, "="
    frame.value.{{ id.id }}.to_s Serial, 16
    Serial.print "\n"
  {% end %}
end

fun kcpuex_handler(frame : Idt::Data::ExceptionRegisters*)
  errcode = frame.value.errcode
  unless process = Multiprocessing::Scheduler.current_process
    dump_frame(frame)
    Serial.print "segfault from pre-startup kernel code?"
    while true; end
  end
  process = process.not_nil!
  case frame.value.int_no
  when EX_PAGEFAULT
    faulting_address = 0u64
    asm("mov %cr2, $0" : "=r"(faulting_address) :: "volatile")

    present = (errcode & 0x1) == 0
    rw = (errcode & 0x2) != 0
    user = (errcode & 0x4) != 0
    reserved = (errcode & 0x8) != 0
    id = (errcode & 0x10) != 0

    Serial.print Pointer(Void).new(faulting_address), user, " ", Pointer(Void).new(frame.value.rip), "\n"
    Serial.print "from ", process.name, '\n'
    while true; end

    {% if false %}
      if process.kernel_process?
        panic "segfault from kernel process"
      elsif frame.value.rip > Paging::KERNEL_OFFSET
        panic "segfault from kernel"
      else
        if faulting_address < Multiprocessing::USER_STACK_TOP &&
           faulting_address > Multiprocessing::USER_STACK_BOTTOM_MAX
          # stack page fault
          Idt.disable do
            stack_address = Paging.t_addr(faulting_address)
            process.udata.not_nil!.mmap_list.add(stack_address, 0x1000,
              MemMapNode::Attributes::Read | MemMapNode::Attributes::Write | MemMapNode::Attributes::Stack)

            addr = Paging.alloc_page_pg(stack_address, true, true)
            zero_page Pointer(UInt8).new(addr)
          end
          return
        else
          Multiprocessing::Scheduler.switch_process_and_terminate
        end
      end
    {% end %}
  else
    dump_frame(frame)
    Serial.print "process: ", process.name, '\n'
    Serial.print "unhandled cpu exception: ", frame.value.int_no, ' ', errcode, '\n'
    while true; end
  end
end

{% if flag?(:record_cli) %}
  fun __record_cli : UInt64
    Idt.disabled_at
  end
{% end %}
