// =============================================================================
// axi4lite_env_pkg.sv
// UVM env: contains the agent + scoreboard.
// Scoreboard maintains a shadow memory and checks reads against it.
// =============================================================================
`ifndef AXI4LITE_ENV_PKG_SV
`define AXI4LITE_ENV_PKG_SV

package axi4lite_env_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import axi4lite_pkg::*;

    // ----------------------------------------------------------------------
    // Scoreboard
    //   Subscribes to the agent monitor.
    //   On WRITE: stores expected data in shadow memory (indexed by word addr).
    //   On READ : compares observed RDATA against shadow memory.
    // ----------------------------------------------------------------------
    class axi4lite_scoreboard extends uvm_subscriber #(axi4lite_txn);

        `uvm_component_utils(axi4lite_scoreboard)

        // Shadow memory: 8 word entries (5-bit addr space, word-aligned)
        bit [31:0] shadow_mem [bit [2:0]];

        int unsigned n_writes;
        int unsigned n_reads;
        int unsigned n_mismatches;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void write(axi4lite_txn t);
            bit [2:0] idx = t.addr[4:2];

            if (t.kind == AXI_WRITE) begin
                shadow_mem[idx] = t.data;
                n_writes++;
                `uvm_info("SB", $sformatf("WRITE addr=0x%02h data=0x%08h",
                          t.addr, t.data), UVM_MEDIUM)
            end else begin
                n_reads++;
                if (shadow_mem.exists(idx)) begin
                    bit [31:0] exp = shadow_mem[idx];
                    if (t.data !== exp) begin
                        n_mismatches++;
                        `uvm_error("SB", $sformatf(
                            "READ MISMATCH addr=0x%02h got=0x%08h exp=0x%08h",
                            t.addr, t.data, exp))
                    end else begin
                        `uvm_info("SB", $sformatf(
                            "READ OK   addr=0x%02h data=0x%08h",
                            t.addr, t.data), UVM_MEDIUM)
                    end
                end else begin
                    // First read of this address — no expected value yet.
                    `uvm_info("SB", $sformatf(
                        "READ (no expected) addr=0x%02h data=0x%08h",
                        t.addr, t.data), UVM_LOW)
                end
            end
        endfunction

        function void report_phase(uvm_phase phase);
            `uvm_info("SB", $sformatf(
                "Scoreboard summary: writes=%0d reads=%0d mismatches=%0d",
                n_writes, n_reads, n_mismatches), UVM_NONE)
            if (n_mismatches != 0)
                `uvm_error("SB", "Test failed: read mismatches detected")
        endfunction

    endclass : axi4lite_scoreboard


    // ----------------------------------------------------------------------
    // Environment
    // ----------------------------------------------------------------------
    class axi4lite_env extends uvm_env;

        axi4lite_agent      agent;
        axi4lite_scoreboard sb;

        `uvm_component_utils(axi4lite_env)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent = axi4lite_agent     ::type_id::create("agent", this);
            sb    = axi4lite_scoreboard::type_id::create("sb",    this);
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            agent.mon.ap.connect(sb.analysis_export);
        endfunction

    endclass : axi4lite_env

endpackage : axi4lite_env_pkg

`endif // AXI4LITE_ENV_PKG_SV
