module VFS
  extend self

  class Message
    @next_msg : Message? = nil
    property next_msg

    def slice_size
      @slice.not_nil!.size
    end

    @offset = 0
    getter offset

    getter process
    getter vfs_node
    getter udata
    getter type

    enum Type
      Read
      Write
      Spawn
      PopulateDirectory
    end

    def initialize(@type : Type,
                   @slice : Slice(UInt8)?,
                   @process : Multiprocessing::Process?,
                   @fd : FileDescriptor?,
                   @vfs_node : Node)
    end

    def initialize(@udata : Multiprocessing::Process::UserData?,
                   @vfs_node : Node,
                   @process : Multiprocessing::Process? = nil,
                   @type = Message::Type::Spawn)
    end

    def initialize(@vfs_node : Node,
                   @process : Multiprocessing::Process? = nil,
                   @type = Message::Type::PopulateDirectory)
    end

    def buffering
      return Node::Buffering::Unbuffered if @fd.nil?
      @fd.not_nil!.buffering
    end

    def file_offset
      if @fd.nil?
        0
      else
        @fd.not_nil!.offset
      end
    end

    def consume
      if @offset > 0
        @process.not_nil!.write_to_virtual(@slice.not_nil!.to_unsafe + @offset, 0u8)
        @offset -= 1
      end
    end

    private def finish
      @offset = slice_size
    end

    def finished?
      offset >= slice_size
    end

    def read(&block)
      remaining = slice_size
      # Serial.print "rem:" , remaining, '\n'
      # offset of byte to be written in page (0 -> 0x1000)
      pg_offset = @slice.not_nil!.to_unsafe.address & 0xFFF
      # virtual page range
      virt_pg_addr = Paging.aligned_floor(@slice.not_nil!.to_unsafe.address)
      virt_pg_end = Paging.aligned(@slice.not_nil!.to_unsafe.address + remaining)
      # Serial.print "paddr:" , Pointer(Void).new(virt_pg_addr), " ", Pointer(Void).new(virt_pg_end), '\n'
      while virt_pg_addr < virt_pg_end
        # physical address of the current page
        phys_pg_addr = @process.not_nil!.physical_page_for_address(virt_pg_addr)
        # Serial.print phys_pg_addr, '\n'
        if phys_pg_addr.nil?
          # Serial.print "unable to read\n"
          finish
          return
        end
        phys_pg_addr = phys_pg_addr.not_nil!
        while remaining > 0 && pg_offset < 0x1000
          # Serial.print phys_pg_addr + pg_offset, '\n'
          yield phys_pg_addr[pg_offset]
          remaining -= 1
          pg_offset += 1
        end
        pg_offset = 0
        virt_pg_addr += 0x1000
      end
    end

    def respond(buf : Slice(UInt8))
      pslice = @slice.not_nil!
      process = @process.not_nil!
      remaining = Math.min(buf.size, slice_size - @offset)
      # virtual addresses
      page_start_u = pslice.to_unsafe.address + @offset
      page_start = Paging.aligned_floor(page_start_u)
      page_end = Paging.aligned(pslice.to_unsafe.address + pslice.size)
      p_offset = page_start_u & 0xFFF
      # loop!
      b_offset = 0
      while page_start < page_end && remaining > 0
        copy_sz = Math.min(0x1000 - p_offset, remaining)
        if physical_page = process.physical_page_for_address(page_start)
          memcpy(physical_page + p_offset, buf.to_unsafe + b_offset, copy_sz.to_usize)
        else
          finish
          return @offset
        end
        remaining -= copy_sz
        b_offset += copy_sz
        @offset += copy_sz
        p_offset = 0
        page_start += 0x1000
      end
      @offset
    end

    def respond(ch : UInt8)
      unless finished?
        unless @process.not_nil!.write_to_virtual(@slice.not_nil!.to_unsafe + @offset, ch.to_u8)
          finish
          return
        end
        @offset += 1
      end
    end

    def unawait_no_return
      return false if @process.not_nil!.sched_data.status == Multiprocessing::Scheduler::ProcessData::Status::Normal
      @process.not_nil!.sched_data.status = Multiprocessing::Scheduler::ProcessData::Status::Normal
      true
    end

    def unawait
      return if !unawait_no_return
      if @fd
        @fd.not_nil!.offset += @offset
      end
      @process.not_nil!.frame.rax = @offset
    end

    def unawait(retval)
      return if !unawait_no_return
      @process.not_nil!.frame.rax = retval
    end

    # wakes up the process and have it redo the syscall
    def unawait_rewind
      return if !unawait_no_return
      # 2 = sizeof(syscall/sysenter instruction)
      rip = @process.not_nil!.frame.rip
      @process.not_nil!.frame.rip = rip - 2
    end
  end

  class Queue
    @first_msg : Message? = nil
    @last_msg : Message? = nil

    def initialize(@wake_process : Multiprocessing::Process? = nil)
    end

    def empty?
      @first_msg.nil?
    end

    def enqueue(msg : Message)
      if @first_msg.nil?
        @first_msg = msg
        @last_msg = msg
        msg.next_msg = nil
      else
        @last_msg.not_nil!.next_msg = msg
        @last_msg = msg
      end
      if @wake_process
        @wake_process.not_nil!.sched_data.status =
          Multiprocessing::Scheduler::ProcessData::Status::Normal
      end
    end

    def dequeue
      if msg = @first_msg
        @first_msg = msg.not_nil!.next_msg
        msg
      end
    end

    def keep_if(&block : Message -> _)
      prev = nil
      cur = @first_msg
      until (c = cur).nil?
        c = c.not_nil!
        if yield c
          prev = c
        else
          if prev.nil?
            @first_msg = c.next_msg
          else
            prev.next_msg = nil
          end
        end
        cur = c.next_msg
      end
    end
  end
end
