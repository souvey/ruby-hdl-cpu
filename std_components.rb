class Memory < Array
  include CircuitComponent
  inputs :address, :write_data, :mem_write
  outputs :data

  # Read binary file in Little Endian format
  def self.from_dump(filename)
    return Memory.new(File.open(filename).read.unpack("C*"))
  end

  def execute
    output.data = self[input.address.to_i, 4].pack("C*").unpack("V*")[0]
  end

  # In real life, memory doesn't use the regular clock, but I don't want to
  # actually  write data until the end of the cycle to avoid clobbering memory
  # during intermediately calculations (since address and value don't update
  # simultaneously)
  def tick
    address = input.address.to_i
    data = [input.write_data.to_i].pack("V*").unpack("C*")
    if (input.mem_write==1 && address < length)
      data.each_with_index{|d, i|
        self[address + i] = d
      }
    end
  end

  def to_s
    output = ""
    previous_qword = nil
    already_displayed_asterisk = false
    each_slice(16).each_with_index do |qword, address|
      if qword == previous_qword
        output += "*\n" unless already_displayed_asterisk
        already_displayed_asterisk = true
      else
        already_displayed_asterisk = false
        bytes = qword.map{|x| x || 0}
        ascii = bytes.map{|b| b>31 && b<127 ? b.chr : "."}.join
        output += "%08x  #{"#{"%02x " * 8} " * 2}|%s|\n" %
            [address*16, bytes, ascii].flatten
      end
      previous_qword = qword
    end
    # Include the length of memory to indicate the end
    return output + "%08x" % (length*4)
  end
end

class Adder
  include CircuitComponent
  inputs :in1, :in2
  outputs :sum

  def execute
    output.sum = input.in1.to_i + input.in2.to_i
  end
end

# Sign-extend a 16 bit integer into a 32 bit integer
class Extender16to32
  include CircuitComponent
  inputs :number
  outputs :extended

  def execute
    output.extended = [input.number.to_i].pack("S").unpack("s")[0]
  end
end

class BitSlicer
  include CircuitComponent
  inputs :number
  outputs :sliced

  def initialize(from, to)
    @from = from
    @to = to
  end

  def execute
    output.sliced = (input.number.to_i >> @to) & 2**(@from-@to+1)-1
  end
end

class LeftShifter
  include CircuitComponent
  inputs :number
  outputs :shifted

  def initialize(amount)
    @amount = amount
  end

  def execute
    output.shifted = input.number.to_i << @amount
  end
end

class AndGate
  include CircuitComponent
  inputs :in1, :in2
  outputs :result

  def execute
    output.result = input.in1.to_i & input.in2.to_i
  end
end

class NotGate
  include CircuitComponent
  inputs :in
  outputs :result

  def execute
    output.result = input.in==1 ? 0 : 1
  end
end

class OrGate
  include CircuitComponent
  inputs :in1, :in2
  outputs :result

  def execute
    output.result = input.in1.to_i | input.in2.to_i
  end
end

class EqualityTest
  include CircuitComponent
  inputs :in1, :in2
  outputs :result

  def execute
    output.result = input.in1 == input.in2 ? 1 : 0
  end
end

class Mux
  include CircuitComponent
  inputs :selector
  outputs :selected

  def initialize(count = 2)
    # Uses metaprogramming to define the inputs at runtime
    metaclass = (class << self; self; end)
    @names = ((1..count).map{|i| "in#{i}".to_sym})
    metaclass.inputs *@names
    @value_inputs = @names.map{|n| self.send(n)}
  end

  def [](x)
    values[x]
  end

  def values
    @value_inputs
  end

  def execute
    output.selected = @names.map{|n| input[n]}[input.selector.to_i]
  end
end

class Register
  include CircuitComponent
  inputs :in
  outputs :out

  def initialize(value=nil)
    @midtick = value
    @stored = value
  end

  # Because all registers are not updated simulatenously, to prevent
  # data loss, when a clock ticks, store the current value, but do
  # not output it yet. Output it once all registers have saved their value
  # (tick)
  def tick_prep
    @midtick = input.in
  end

  def tick
    @stored = @midtick
    execute
  end

  def execute
    output.out = @stored
  end

  def reset
    self << @stored
  end

  # For debugging only!
  def value
    @stored
  end
end

class RegisterBank
  include CircuitComponent
  inputs :read_reg_1, :read_reg_2, :write_reg, :write_data, :reg_write
  outputs :read_data_1, :read_data_2

  def initialize(count = 32)
    @registers = Array.new(count){Register.new}
    @count = count
    @mux1 = Mux.new(count + 1)
    @mux2 = Mux.new(count + 1)
    count.times do |i|
      @registers[i] >> @mux1[i]
      @registers[i] >> @mux2[i]
    end
    @mux1 >> output.read_data_1
    @mux2 >> output.read_data_2
  end

  def execute
    @registers.each{|r| r.reset}
    if input.reg_write == 1
      @registers[input.write_reg.to_i] << input.write_data
    end
    # Avoid RAW hazard by having writing "happen before" reading
    # Basically link the write data to the read data when they match,
    # since the actual register won't update until the end of the cycle
    if (input.read_reg_1 == input.write_reg && input.reg_write==1)
      @mux1[-1] << input.write_data
      @mux1.selector << @count
    else 
      @mux1.selector << input.read_reg_1
    end
    if (input.read_reg_2 == input.write_reg && input.reg_write==1)
      @mux2[-1] << input.write_data
      @mux2.selector << @count
    else
      @mux2.selector << input.read_reg_2
    end
  end

  def tick_prep
    @registers.each{|r| r.tick_prep}
  end

  def tick
    @registers.each{|r| r.tick}
  end

  def to_s
    @registers.each_with_index.map{|x|
      [x[1], x[0].value]
    }.each_slice(4).map{|x|
      x.map{|z| "R%2i : 0x%08X" % z}.join("  |  ")
    }.join("\n")
  end
end

class ALU
  include CircuitComponent

  inputs :in1, :in2, :control
  outputs :zero, :result

  def execute
    result = input.in1.to_i.send(input.control || :+, input.in2.to_i)
    output.result = result
    output.zero = (result==0) ? 1 : 0
  end
end

# A pseudo-component that has no inputs and outputs to the special tick calls
class Clock
  def >> component
    @components ||= []
    case component
    when CircuitComponent
      @components << component
    when Array
      @components += component
    when Hash
      @components += component.values
    end
  end
  def tick
    @components.each do |component|
      component.tick_prep
    end
    @components.each do |component|
      component.tick
    end
  end
end

