Background
==========

I wrote this as a final project for a introductory computer architecture course.
The assignment was to write a cycle-accurate, pipelined CPU-simulator for a limited subset of the MIPS architecture.
We were provided with a sample memory dump to use for testing, which I have included here (matrix.bin).
My implementation is impractical, inefficient, confusing, and ridiculous, and I had a lot of fun writing it :)

Design / Data Structures
========================

Since the class was focused on hardware, not software, I chose the more interesting
approach (the typical design was to parse into high-level classes like "Instruction" and pass them around with methods) of representing the hardware by virtually recreating the 
CPU.s circuit/wiring and components (gates, adders, clock, etc). To do this, I implemented my own 
simple hardware description language in Ruby, wrote a collection of circuit components, and then wired 
up the CPU using my language. The language is implemented using metaprogramming in Ruby to define 
a DSL. Circuits are defined by their components, which are Ruby classes/objects, and the wires
(represented in a custom syntax and internally as functions/lambdas) between the inputs and outputs of 
those components. Outputs maintain their state until they are changed, which triggers a recursive 
recalculation of all the components connected to them. This means that circuits can be connected to 
themselves without created an infinitely loop.

A component is created as follows:

    class ComponentName
      include CircuitComponent
      inputs :input_name, :another_input_name, ...
      outputs :output_name, :and_another, ...
      def execute
        output.output_name = somerubyfunction(input.input_name)
        ...
      end
    end

The syntax for wiring components together is:

    component1.output_name >> component2.input_name

It is possible to leave out the input/output name if there is only one:

    not_gate1 >> not_gate2

Additionally, wires can be changed together:

    X >> Y >> Z    == >   X >> Y; Y >> Z

A constant can be hardwired to an input as follows:

    adder.input2 << 4

Finally, some components, such as a Mux, have a shorthand syntax for accessing inputs:

    component1.output >> mux[1]
    
Code Organization
=================

* simulator.rb: Contains the wiring for the CPU itself using the custom HDL, as well as the code for 
running and debugging it from the command land
* hdl.rb: Contains the custom hardware description language described above in .Design.
* std_components.rb: Contains standard hardware components for use with the HDL
  * Memory, Adder, Extender16to32 (sign extension), BitSlicer (ex: 10111 sliced from 4 to 0 
= 0111), LeftShifter, AndGate / OrGate / NotGate, EqualityTest, Mux (any size), Register, 
RegisterBank (any size), ALU (only with operations needed for this CPU), Clock
* cpu_components.rb: Contains special hardware components used specifically for this pipeline
  * Control, ALUControl, ForwardingUnit, HazardDetectionUnit, System

Usage / Debugging
=================

Note: Requires ruby (tested on v1.8.7)

    Usage: ./simulator.rb [options] file
        -t, --terminate N                Terminate after N cycles
        -h, --help                       Show this message.
      At each cycle:
        -w, --wait                       Wait for user input
        -r, --registers                  Print register bank
        -m, --memory                     Print memory
        -i, --instructions               Print pipelined instructions
        -p, --pipeline                   Print pipeline registers
        -c, --circuit                    Print inputs/outputs to all circuit components
        -v, --verbose                    Print all debugging information

Note: Wait/interactive (-w) mode runs one cycle at a time, printing any 
debugging output and then waiting for a newline to be entered into the console. Additionally, it is 
possible to quit the simulation and print out the current results at any time by typing .q. (then enter).

Sample Output
=============

    ./simulator.rb matrix.bin
    
    Instructions: 100 | Cycles: 123 | CPI: 1.23
    R 0 : 0x00000000  |  R 1 : 0x00000000  |  R 2 : 0x00000020  |  R 3 : 0x00000012
    R 4 : 0x00000000  |  R 5 : 0x00000000  |  R 6 : 0x00000000  |  R 7 : 0x00000000
    R 8 : 0x00000003  |  R 9 : 0x00000006  |  R10 : 0x00000009  |  R11 : 0x0000000C
    R12 : 0x0000000F  |  R13 : 0x00000012  |  R14 : 0x00000015  |  R15 : 0x00000018
    R16 : 0x00000000  |  R17 : 0x00000000  |  R18 : 0x00000000  |  R19 : 0x00000000
    R20 : 0x00000000  |  R21 : 0x00000000  |  R22 : 0x00000000  |  R23 : 0x00000000
    R24 : 0x0000001B  |  R25 : 0x00000024  |  R26 : 0x00000000  |  R27 : 0x00000000
    R28 : 0x00000000  |  R29 : 0x00000000  |  R30 : 0x00000000  |  R31 : 0x00000000
