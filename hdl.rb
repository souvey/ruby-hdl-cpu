require 'set'
# A simple DSL I designed for circuit simulation
# Has a base mixin of CircuitComponent with allows classes to be
# "wired" together
module CircuitComponent
  # An input of a component, which is a function that sets the input
  # and executes the component
  class Input < Proc
    # Shorthand notation for setting the value of an input
    alias_method :<<, :call
  end

  # An output of a component, which may be wired to many other component inputs
  class Output
    def initialize
      @inputs = Set.new
    end
    def set(value)
      # To allow the circuit to terminate even in cyclic circuits (those with
      # wires that feed into themselves), only resimulate a wire if the data
      # it is carrying changes
      if value != @existing_value
        @existing_value = value
        @inputs.each{|input| input << value}
      end
    end
    # Add a wire from this output to the given destination (output, component, or input)
    def >>(destination)
      if (destination.class == Output)
        # create an intermediary input to wire from an output to an output
        input = Input.new{|val| destination.set(val)}
      elsif (destination.is_a? CircuitComponent)
        input = destination.default_input
      else
        input = destination
      end
      @inputs << input
      # Return the argument to allow method chaining
      destination
    end
    def inspect
      @existing_value.inspect
    end
  end

  # A convenience class for accessing inputs and outputs within a component
  #   hash.input         =>   hash[:input]
  #   hash.output = x    =>   hash[:output].set(x)  
  class IOHash < Hash
    def method_missing(meth, *args, &block)
      if meth.to_s[-1,1] == '='
        self[meth.to_s[0..-2].to_sym].set(args[0])
      else
        self[meth]
      end
    end
  end

  # Class methods (static methods) for setting up inputs and ouputs
  # Uses ruby metaprogramming to create dynamically methods in the class
  module ClassMethods
    # Setup the given inputs and create accessors
    def inputs(*names)
      names.each do |name|
        define_method(name.to_sym) do
          inputs[name.to_sym]
        end
      end
      alias_method :default_input, names.first.to_sym
    end

    # Setup the given outputs and create accessors
    def outputs(*names)
      names.each do |name|
        define_method(name.to_sym) do
          output[name.to_sym]
        end
      end
      alias_method :default_output, names.first.to_sym
    end
  end

  # Lazy initialize the list of input values
  def input
    @input_vals ||= IOHash.new
  end

  # Lazy initalize the list of inputs and lazily create them
  def inputs
    @inputs ||= Hash.new do |hash, key|
      hash[key] = Input.new do |value|
        input[key] = value
        execute
      end
    end
  end

  # Lazy initialize the list of outputs and lazily create those outputs
  def output
    @outputs ||= IOHash.new{|hash, key| hash[key] = Output.new}
  end

  # Include the "inputs" and "outputs" methods as class (static) methods 
  def self.included(base)
    base.extend ClassMethods
  end

  # Shorthand for wiring out from components with only one output
  # Ex: register >> component.in  =>  register.output >> component.in
  def >>(x)
    default_output >> x
  end

  # Shorthand for setting the input value of components with just one input
  # Ex: register << 5  =>  register.input << 5
  def <<(x)
    default_input << x
  end

  # Called on components when the clock ticks (before any tick is called)
  def tick_prep; end

  # Called on components when the clock ticks (after all tick_preps are done)
  def tick; end

  # Use inputs and produce new ouputs
  def execute; end

  # Debugging print-out
  def inspect
     "<#{self.class.name}>, in: #{input.inspect}, out: #{output.inspect}" 
  end

  # Call the execute method on all components in memory (via GC)
  def self.start_all
    ObjectSpace.each_object(CircuitComponent){|n| n.execute}
  end
end
