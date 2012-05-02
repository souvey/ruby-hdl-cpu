class Control
  include CircuitComponent

  RTYPE = 0x00
  ADDI = 0x08
  BEQ = 0x04
  J = 0x02
  LW = 0x23
  SW = 0x2B
  HLT = 0x3F
  inputs :opcode
  outputs :reg_dst, :jump, :branch, :mem_to_reg, :mem_read,
          :alu_op, :mem_write, :alu_src, :reg_write, :debug_name,
          :terminate

  NAME = {0x00 => "rtype", 0x08 => "addi", 0x04 => "beq",
          0x02 => "j", 0x23 => "lw", 0x2b => "sw", 0x3f => "hlt"}
  def execute
    output.branch = input.opcode == BEQ ? 1 : 0
    output.jump = input.opcode == J ? 1 : 0
    output.mem_write = input.opcode == SW ? 1 : 0
    output.reg_write = [RTYPE, ADDI, LW].include?(input.opcode) ? 1 : 0
    output.reg_dst = input.opcode == RTYPE ? 1 : 0
    output.alu_src = [ADDI, LW, SW].include?(input.opcode) ? 1 : 0
    output.mem_to_reg = input.opcode == LW ? 1 : 0
    output.mem_read = input.opcode == LW ? 1 : 0
    output.debug_name = Control.instr_name(input.opcode)
    output.alu_op = case input.opcode
      when RTYPE; :f
      when BEQ; :-
      else :+
    end
    output.terminate = input.opcode == HLT ? 1 : 0
  end

  def Control.instr_name(opcode)
    NAME[opcode]
  end
end

class ALUControl
  include CircuitComponent

  inputs :function, :alu_op
  outputs :control
  
  def execute
   if input.alu_op == :f
     case input.function
     when 0x20
       output.control = :+
     end
   else
     output.control = input.alu_op
   end
  end
end

class ForwardingUnit
  include CircuitComponent

  inputs :ex_mem_reg_write, :mem_wb_reg_write,
         :ex_mem_reg_rd, :mem_wb_reg_rd,
         :id_ex_reg_rt, :id_ex_reg_rs
  outputs :forward_a, :forward_b

  def execute
    # Copied from textbook (with bug fix)
    if (input.ex_mem_reg_write == 1 &&
           input.ex_mem_reg_rd != 0 &&
           input.ex_mem_reg_rd == input.id_ex_reg_rs)
      output.forward_a = 2
    elsif (input.mem_wb_reg_write==1 &&
        input.mem_wb_reg_rd != 0 &&
        input.mem_wb_reg_rd == input.id_ex_reg_rs)
      output.forward_a = 1
    else
      output.forward_a = 0
    end

    if (input.ex_mem_reg_write == 1 &&
           input.ex_mem_reg_rd != 0 &&
           input.ex_mem_reg_rd == input.id_ex_reg_rt)
      output.forward_b = 2
    elsif (input.mem_wb_reg_write==1 &&
        input.mem_wb_reg_rd != 0 &&
        input.mem_wb_reg_rd == input.id_ex_reg_rt)
      output.forward_b = 1
    else
      output.forward_b = 0
    end
  end
end

class HazardDetectionUnit
  include CircuitComponent

  inputs :id_ex_mem_read, :id_ex_reg_rt,
         :if_id_reg_rs, :if_id_reg_rt
  outputs :pc_write, :if_id_write, :nop

  def execute
    if (input.id_ex_mem_read == 1 &&
        (input.id_ex_reg_rt == input.if_id_reg_rs ||
         input.id_ex_reg_rt == input.if_id_reg_rt))
      output.nop = 1
      output.pc_write = 0
      output.if_id_write = 0
    else
      output.nop = 0
      output.pc_write = 1
      output.if_id_write = 1
    end
  end
end

class System
  include CircuitComponent

  inputs :terminate
  inputs :real

  def tick_prep
    @_terminate = input.terminate
    @_real = input.real
  end

  def tick
    @terminate = @_terminate
    @count ||= 0
    if @_real == 1
      @count += 1
    end
  end

  def terminate?
    @terminate==1
  end

  def instructions
    @count
  end
end


