// =============================================================================
// tb_top.sv
// Testbench top: clock + reset, DUT, interface, kicks off run_test().
// =============================================================================
`ifndef TB_TOP_SV
`define TB_TOP_SV

`timescale 1ns/1ps

module tb_top;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import axi4lite_pkg::*;
    import axi4lite_env_pkg::*;
    import axi4lite_tests_pkg::*;

    // -------------------- Clock & Reset --------------------
    logic aclk    = 1'b0;
    logic aresetn = 1'b0;

    always #5 aclk = ~aclk; // 100 MHz

    initial begin
        aresetn = 1'b0;
        repeat (5) @(posedge aclk);
        aresetn = 1'b1;
    end

    // -------------------- Interface --------------------
    axi4lite_if #(.ADDR_WIDTH(5), .DATA_WIDTH(32)) vif (.aclk(aclk), .aresetn(aresetn));

    // -------------------- DUT --------------------
    // FV observation ports: outputs left dangling, inputs tied to 0.
    wire [1:0]  unused_w_state, unused_r_state;
    wire [4:0]  unused_waddr_q, unused_raddr_q;
    wire [31:0] unused_mem_at_watch;

    axi4lite_slave #(.ADDR_WIDTH(5), .DATA_WIDTH(32)) dut (
        .aclk    (aclk),
        .aresetn (aresetn),

        .awaddr  (vif.awaddr),
        .awvalid (vif.awvalid),
        .awready (vif.awready),

        .wdata   (vif.wdata),
        .wstrb   (vif.wstrb),
        .wvalid  (vif.wvalid),
        .wready  (vif.wready),

        .bresp   (vif.bresp),
        .bvalid  (vif.bvalid),
        .bready  (vif.bready),

        .araddr  (vif.araddr),
        .arvalid (vif.arvalid),
        .arready (vif.arready),

        .rdata   (vif.rdata),
        .rresp   (vif.rresp),
        .rvalid  (vif.rvalid),
        .rready  (vif.rready),

        // FV observation ports — tie off for sim
        .fv_w_state      (unused_w_state),
        .fv_r_state      (unused_r_state),
        .fv_waddr_q      (unused_waddr_q),
        .fv_raddr_q      (unused_raddr_q),
        .fv_watch_idx    (3'b000),
        .fv_mem_at_watch (unused_mem_at_watch)
    );

    // -------------------- UVM run --------------------
    initial begin
        uvm_config_db#(virtual axi4lite_if)::set(null, "*", "vif", vif);
        // EPWave dump for EDA Playground
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_top);
        run_test();
    end

endmodule

`endif // TB_TOP_SV
