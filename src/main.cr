require "./core.cr"
require "./fs.cr"
require "./drivers/core/*"
require "./drivers/arch/*"
require "./drivers/**"
require "./arch/gdt.cr"
require "./arch/idt.cr"
require "./arch/paging.cr"
require "./arch/multiboot.cr"
require "./arch/cpuid.cr"
require "./alloc/*"
require "./multiprocessing/*"

lib Kernel
  fun ksyscall_setup
  fun ksetup_fxsave_region_base

  $fxsave_region_ptr : UInt8*
  $fxsave_region_base_ptr : UInt8*
  $kernel_end : Void*
  $text_start : Void*; $text_end : Void*
  $data_start : Void*; $data_end : Void*
  $stack_start : Void*; $stack_end : Void*
  $int_stack_start : Void*; $int_stack_end : Void*
end

MAIN_PROGRAM = "/main"

fun kmain(mboot_magic : UInt32, mboot_header : Multiboot::MultibootInfo*)
  if mboot_magic != MULTIBOOT_BOOTLOADER_MAGIC
    abort "Kernel should be booted from a multiboot bootloader!"
  end

  Multiprocessing.fxsave_region = Kernel.fxsave_region_ptr
  Multiprocessing.fxsave_region_base = Kernel.fxsave_region_base_ptr
  Kernel.ksetup_fxsave_region_base

  VGA.init_device

  Console.print "Booting lilith...\n"

  Console.print "initializing gdtr...\n"
  Gdt.init_table

  # timer
  PIT.init_device

  # paging
  Console.print "initializing paging...\n"
  # use the physical address of the kernel end for pmalloc
  Pmalloc.start = Paging.aligned(Kernel.kernel_end.address - Paging::KERNEL_OFFSET)
  Pmalloc.addr = Pmalloc.start
  Paging.init_table(Kernel.text_start, Kernel.text_end,
    Kernel.data_start, Kernel.data_end,
    Kernel.stack_start, Kernel.stack_end,
    Kernel.int_stack_start, Kernel.int_stack_end,
    mboot_header)

  Console.print "physical memory detected: ", Paging.usable_physical_memory, " bytes\n"

  # gc
  Console.print "initializing kernel garbage collector...\n"
  Allocator.init(Kernel.int_stack_end.address + 0x1000)
  GC.init Kernel.stack_start, Kernel.stack_end

  # processes
  Gdt.register_int_stack Kernel.int_stack_end
  Gdt.flush_tss
  Kernel.ksyscall_setup

  # interrupts
  Console.print "initializing idt...\n"
  PIC.init_interrupts
  Idt.init_table
  Idt.enable

  # hardware
  # pci
  Console.print "checking PCI buses...\n"
  PCI.check_all_buses do |bus, device, func, vendor_id|
    device_id = PCI.read_field bus, device, func, PCI::PCI_DEVICE_ID, 2
    if Ide.pci_device?(vendor_id, device_id)
      Ide.init_controller bus, device, func
    elsif BGA.pci_device?(vendor_id, device_id)
      BGA.init_controller bus, device, func
      Console.text_mode = false
    end
  end

  # time
  Time.stamp = RTC.unix

  # ps2 controller
  PS2.init_controller

  # initial rootfs
  Multiprocessing.procfs = ProcFS::FS.new
  RootFS.append(Multiprocessing.procfs.not_nil!)
  RootFS.append(KbdFS::FS.new(Keyboard.new))
  RootFS.append(MouseFS::FS.new(Mouse.new))
  RootFS.append(ConsoleFS::FS.new)
  RootFS.append(SerialFS::FS.new)
  RootFS.append(FbdevFS::FS.new)
  RootFS.append(PipeFS::FS.new)
  RootFS.append(TmpFS::FS.new)
  RootFS.append(SocketFS::FS.new)

  # file systems
  root_device = Ide.devices[0]
  if root_device.nil?
    abort "no disk found!"
  end
  root_device = root_device.not_nil!

  main_bin : VFS::Node? = nil
  if (mbr = MBR.read(root_device))
    Console.print "found MBR header...\n"
    fs = Fat16FS::FS.new root_device, mbr.to_unsafe.value.partitions[0]
    if !fs.root.dir_populated
      case fs.root.populate_directory
      when VFS_OK
        # ignored
      when VFS_WAIT
        abort "TODO"
      end
    end
    fs.root.each_child do |node|
      if node.name == "main"
        main_bin = node
      end
    end
    RootFS.append(fs)
  else
    abort "can't boot from this device"
  end

  # load main.bin
  if main_bin.nil?
    Console.print "no main.bin detected.\n"
    while true
    end
  else
    Console.print "executing MAIN.BIN...\n"

    builder = String::Builder.new(1 + fs.not_nil!.name.bytesize)
    builder << "/"
    builder << fs.not_nil!.name
    main_path = builder.to_s

    argv = Array(String).new 0
    builder.reset(main_path.bytesize + MAIN_PROGRAM.bytesize)
    builder << main_path
    builder << MAIN_PROGRAM
    argv.push builder.to_s

    udata = Multiprocessing::Process::UserData
      .new(argv,
        main_path,
        fs.not_nil!.root)
    udata.setenv("PATH", "/hd0/bin")

    case main_bin.not_nil!.spawn(udata)
    when VFS_ERR
      abort "unable to load main!"
    when VFS_WAIT
      fs.not_nil!.queue.not_nil!
        .enqueue(VFS::Message.new(udata, main_bin))
    end

    # switch to pid 1
    Idt.disable # disable so the cpu doesn't interrupt mid context switch
    Idt.switch_processes = true
    Multiprocessing.first_process.not_nil!
      .initial_switch
  end
end

fun __crystal_once_init : Void*
  Pointer(Void).new 0
end

fun __crystal_once(state : Void*, flag : Bool*, initializer : Void*)
  unless flag.value
    Proc(Nil).new(initializer, Pointer(Void).new 0).call
    flag.value = true
  end
end
