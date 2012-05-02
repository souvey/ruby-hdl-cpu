#!/usr/bin/ruby

require 'optparse'
require 'hdl'
require 'std_components'
require 'cpu_components'

# ====================================
# Parse command line debugging options
# ====================================

options = {}
ARGV.options do |opts|
  script_name = File.basename($0)
  opts.banner = "Usage: ./#{script_name} [options] file"
  opts.on("-t", "--terminate N", Integer, "Terminate after N cycles"){
          |t| options[:terminate] = t}
  opts.on("-h", "--help", "Show this message."){ puts opts; exit }
  opts.separator("  At each cycle:")
  opts.on("-w", "--wait", "Wait for user input"){|w| options[:wait] = w}
  opts.on("-r", "--registers",
          "Print register bank") {|r| options[:registers] = r}
  opts.on("-m", "--memory",
          "Print memory") {|m| options[:memory] = m}
  opts.on("-i", "--instructions",
          "Print pipelined instructions") {
          |i| options[:instructions] = i}
  opts.on("-p", "--pipeline",
          "Print pipeline registers"){
          |p| options[:pipeline] = p}
  opts.on("-c", "--circuit",
          "Print inputs/outputs to all circuit components"){
          |c| options[:circuit] = c }
  opts.on("-v", "--verbose",
          "Print all debugging information"){|v|
            options[:registers] = v
            options[:memory] = v
            options[:pipeline] = v
            options[:circuit] = v
            options[:instructions] = v}
  opts.parse!
  options[:file] = ARGV.first
end

if not options[:file]
  puts ARGV.options.banner
  exit
end

# ===========================================
# Build and wire up the circuit (per diagram)
# ===========================================

# Pipeline Registers
# ------------------
IF_ID = Hash.new{|hash,key| hash[key] = Register.new}
ID_EX = Hash.new{|hash,key| hash[key] = IF_ID[key] >> Register.new}
EX_MEM = Hash.new{|hash,key| hash[key] = ID_EX[key] >> Register.new}
MEM_WB = Hash.new{|hash,key| hash[key] = EX_MEM[key] >> Register.new}
pipeline = [["IF/ID",IF_ID], ["ID/EX",ID_EX], ["EX/MEM",EX_MEM], ["MEM/WB",MEM_WB]]

# Program counter
# ---------------
pc = Register.new(2**12) # with default value

pc_plus_4 = Adder.new
pc >> pc_plus_4.in1
pc_plus_4.in2 << 4

# Initialize important components
# -------------------------------
hazard = HazardDetectionUnit.new
control = Control.new

# Termination detection
# ---------------------
system = System.new
control.terminate >>
  ID_EX[:terminate] >>
    EX_MEM[:terminate] >>
      system.terminate

# Instruction memory
# ------------------
instr_memory = Memory.from_dump(options[:file])
pc >> instr_memory.address

# Instruction stall/flush
# -----------------------
instr_write_mux = Mux.new
hazard.if_id_write >> instr_write_mux.selector
instr_memory >> instr_write_mux[1] 

flush_mux = Mux.new
instr_write_mux >> flush_mux[0]
flush_mux[1] << 0

# Instruction Parsing
# -------------------
instr = flush_mux >> IF_ID[:instr]
instr >> BitSlicer.new(31, 26) >> control.opcode
instr_rs = instr >> BitSlicer.new(25, 21)
instr_rt = instr >> BitSlicer.new(20, 16)
instr_rd = instr >> BitSlicer.new(15, 11)
instr_immediate = instr >> BitSlicer.new(15, 0) >> Extender16to32.new

instr >> instr_write_mux[0]

# Register Bank
# -------------
registers = RegisterBank.new

reg_write_or_nop = Mux.new
control.reg_write >> reg_write_or_nop[0]
reg_write_or_nop[1] << 0
hazard.nop >> reg_write_or_nop.selector
reg_write_or_nop >>
  ID_EX[:reg_write] >>
    EX_MEM[:reg_write] >>
      MEM_WB[:reg_write] >>
        registers.reg_write

instr_rs >> registers.read_reg_1
instr_rt >> registers.read_reg_2
registers.read_data_2 >> ID_EX[:read_data_2]

reg_dst_mux = Mux.new
control.reg_dst >> ID_EX[:reg_dst] >> reg_dst_mux.selector
instr_rt >> ID_EX[:instr_rt] >> reg_dst_mux[0]
instr_rd >> ID_EX[:instr_rd] >> reg_dst_mux[1]
reg_dst_mux >> EX_MEM[:write_reg] >> MEM_WB[:write_reg] >> registers.write_reg

# Hazards
# -------
control.mem_read >> ID_EX[:mem_read] >> hazard.id_ex_mem_read
ID_EX[:instr_rt] >> hazard.id_ex_reg_rt
instr_rt >> hazard.if_id_reg_rt
instr_rs >> hazard.if_id_reg_rs

# Forwarding
# ----------
forwarding = ForwardingUnit.new
EX_MEM[:reg_write] >> forwarding.ex_mem_reg_write
EX_MEM[:write_reg] >> forwarding.ex_mem_reg_rd
MEM_WB[:reg_write] >> forwarding.mem_wb_reg_write
MEM_WB[:write_reg] >> forwarding.mem_wb_reg_rd
ID_EX[:instr_rt] >> forwarding.id_ex_reg_rt
instr_rs >> ID_EX[:instr_rs] >> forwarding.id_ex_reg_rs

forward_a = Mux.new(3)
forwarding.forward_a >> forward_a.selector
registers.read_data_1 >> ID_EX[:read_data_1] >> forward_a[0]

forward_b = Mux.new(3)
forwarding.forward_b >> forward_b.selector
ID_EX[:read_data_2] >> forward_b[0]
forward_b >> EX_MEM[:forward_b_data]

# ALU
# ---
alu_src_mux = Mux.new
control.alu_src >> ID_EX[:alu_src] >> alu_src_mux.selector
forward_b >> alu_src_mux[0]
instr_immediate >> ID_EX[:instr_immediate] >> alu_src_mux[1]

alu = ALU.new
forward_a >> alu.in1
alu_src_mux >> alu.in2

alu_control = ALUControl.new
instr >> BitSlicer.new(5, 0) >> alu_control.function
control.alu_op >> ID_EX[:alu_op] >> alu_control.alu_op
alu_control >> alu.control

# Branching and jumping
# ---------------------
branch_adder = Adder.new
pc >> branch_adder.in1
instr_immediate >> LeftShifter.new(2) >> branch_adder.in2

branch_equal = EqualityTest.new
registers.read_data_1 >> branch_equal.in1
registers.read_data_2 >> branch_equal.in2

branch_and = AndGate.new
control.branch >> branch_and.in1
branch_equal >> branch_and.in2

branch_mux = Mux.new
pc_plus_4 >> branch_mux[0]
branch_adder >> branch_mux[1]
branch_and >> branch_mux.selector

jump_mux = Mux.new
branch_mux >> jump_mux[0]
instr >> BitSlicer.new(25, 0) >> LeftShifter.new(2) >> jump_mux[1]
control.jump >> jump_mux.selector

branch_or_jump = OrGate.new
control.jump >> branch_or_jump.in1
branch_and >> branch_or_jump.in2
# Don't load instruction after a halt
branch_or_jump >> flush_mux.selector
branch_or_jump >> IF_ID[:flushed]

pc_write_mux = Mux.new
pc >> pc_write_mux[0]
jump_mux >> pc_write_mux[1]
hazard.pc_write >> pc_write_mux.selector
pc_write_mux >> pc

# Data memory
# ------
data_memory = Memory.new(instr_memory)
alu.result >> EX_MEM[:alu_result] >> data_memory.address
EX_MEM[:alu_result] >> forward_a[2]
EX_MEM[:alu_result] >> forward_b[2]
EX_MEM[:forward_b_data] >> data_memory.write_data

mem_write_or_nop = Mux.new
control.mem_write >> mem_write_or_nop[0]
mem_write_or_nop[1] << 0
hazard.nop >> mem_write_or_nop.selector
mem_write_or_nop >>
  ID_EX[:mem_write] >> 
    EX_MEM[:mem_write] >>
      data_memory.mem_write

mem_to_reg_mux = Mux.new
data_memory >> MEM_WB[:read_data] >> mem_to_reg_mux[1]
MEM_WB[:alu_result] >> mem_to_reg_mux[0]
control.mem_to_reg >>
  ID_EX[:mem_to_reg] >>
    EX_MEM[:mem_to_reg] >>
      MEM_WB[:mem_to_reg] >>
        mem_to_reg_mux.selector
mem_to_reg_mux >> registers.write_data
mem_to_reg_mux >> forward_a[1]
mem_to_reg_mux >> forward_b[1]

# Instruction debugging/counting
# ------------------------------
IF_ID[:started] << 1
is_nop = OrGate.new
hazard.nop >> is_nop.in1
IF_ID[:flushed] >> is_nop.in2
is_real = AndGate.new
is_nop >> NotGate.new >> is_real.in1
IF_ID[:started] >> is_real.in2
is_real >> ID_EX[:real] >> EX_MEM[:real] >> MEM_WB[:real] >> system.real
# Pass the debug name through each pipeline register so debug printout
# can show what instruction is in each pipeline stage
control.debug_name >>
  ID_EX[:debug_name] >>
    EX_MEM[:debug_name] >>
      MEM_WB[:debug_name]

# Clock
# -----
clock = Clock.new
clock >> registers
clock >> pc
clock >> data_memory
clock >> system
clock >> IF_ID
clock >> ID_EX
clock >> EX_MEM
clock >> MEM_WB


# ================================
# Execution and output
# ================================

# Send out initial outputs over the wires
CircuitComponent.start_all

if (options[:wait])
  print "Press enter to continue, or q followed by enter to quit"
end

# Excecute the program, with at most the number of cycles given as an argument
cycles = 0
while (cycles < (options[:terminate]||1.0/0.0)) &&
       (!options[:wait] || ($stdin.gets.chomp != "q")) do
  cycles += 1

  debug_output = []
  if options[:instructions]
    if_id_instr = IF_ID[:instr].value!=nil ?
      Control.instr_name(IF_ID[:instr].value >> 26) : ""
    id_ex_instr = ID_EX[:real].value==1 ? ID_EX[:debug_name].value : ""
    ex_mem_instr = EX_MEM[:real].value==1 ? EX_MEM[:debug_name].value : ""
    mem_wb_instr = MEM_WB[:real].value==1 ? MEM_WB[:debug_name].value : ""
    debug_output <<  "IF/ID : #{if_id_instr}  ID/EX : #{id_ex_instr}  " +
                     "EX/MEM: #{ex_mem_instr}  MEM/WB: #{mem_wb_instr}"
  end
  if options[:pipeline]
    pipeline_output = []
    pipeline.each do |stage, regs|
      register_values = Hash[*regs.map{|k,v|[k,v.value]}.flatten]
      pipeline_output << "#{stage}: #{register_values.inspect}"
    end
    debug_output << pipeline_output.join("\n")
  end
  debug_output << registers.to_s if (options[:registers])
  debug_output << data_memory.to_s if (options[:memory])
  if options[:circuit]
    circuit_output = []
    local_variables.sort.each do |name|
      value = eval(name)
      if value.is_a? CircuitComponent
         circuit_output << "#{name} #{value.inspect}"
      end
    end
    debug_output << circuit_output.join("\n")
  end
  
  if (debug_output.size > 0)
    puts "\nInstruction ##{cycles} | PC: #{pc.value}\n\n"
    puts debug_output.join("\n\n")
    puts "\n" + "-" * 80
  elsif options[:wait]
    print "Instruction ##{cycles} | PC: #{pc.value}"
  end

  break if system.terminate?

  clock.tick
end

puts "=" * 80
puts "Final Result"
puts "=" * 80
puts "Instructions: #{system.instructions} | Cycles: #{cycles} " +
     "| CPI: #{cycles.to_f/system.instructions.to_f}"
puts ""
puts registers.to_s
puts ""
puts data_memory.to_s
