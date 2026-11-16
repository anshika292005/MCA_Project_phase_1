`default_nettype none
`timescale 1ns/1ps
// Unit test: addr_decoder. Checks both edges of every region plus invalid addresses.
module tb_addr_decoder;
    reg  [31:0] addr;
    wire        sel_ram, sel_io, addr_fault;
    integer     errors = 0;

    addr_decoder dut (.addr(addr), .sel_ram(sel_ram), .sel_io(sel_io), .addr_fault(addr_fault));

    task check(input [31:0] a, input exp_ram, input exp_io, input exp_fault);
        begin
            addr = a;
            #1;
            if ({sel_ram, sel_io, addr_fault} !== {exp_ram, exp_io, exp_fault}) begin
                $display("FAIL addr=%h got ram/io/fault=%b%b%b expected %b%b%b",
                         a, sel_ram, sel_io, addr_fault, exp_ram, exp_io, exp_fault);
                errors = errors + 1;
            end
        end
    endtask

    initial begin
        $dumpfile("build/tb_addr_decoder.vcd");
        $dumpvars(0, tb_addr_decoder);
        check(32'h0000_0000, 1, 0, 0);   // first RAM word
        check(32'h0000_0100, 1, 0, 0);   // middle
        check(32'h0000_03FC, 1, 0, 0);   // last RAM word
        check(32'h0000_0400, 0, 1, 0);   // out_port
        check(32'h0000_0404, 0, 0, 1);   // just above out_port
        check(32'h0000_0800, 0, 0, 1);
        check(32'h8000_0000, 0, 0, 1);   // high bit set
        check(32'hFFFF_FFFC, 0, 0, 1);
        check(32'h0001_0000, 0, 0, 1);   // would alias to RAM if upper bits were ignored
        if (errors == 0) $display("tb_addr_decoder: PASS");
        else             $display("tb_addr_decoder: FAIL (%0d errors)", errors);
        $finish;
    end
endmodule
`default_nettype wire
