// =============================================================================
// axi4lite_tests_pkg.sv
// UVM tests: base test + Day-1 smoke test.
// Day-2 tests (RAL) will be added in this same package later.
// =============================================================================
`ifndef AXI4LITE_TESTS_PKG_SV
`define AXI4LITE_TESTS_PKG_SV

package axi4lite_tests_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import axi4lite_pkg::*;
    import axi4lite_env_pkg::*;

    // ----------------------------------------------------------------------
    // Base test: builds the env, prints topology
    // ----------------------------------------------------------------------
    class axi4lite_base_test extends uvm_test;

        axi4lite_env env;

        `uvm_component_utils(axi4lite_base_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = axi4lite_env::type_id::create("env", this);
        endfunction

        function void end_of_elaboration_phase(uvm_phase phase);
            uvm_top.print_topology();
        endfunction

    endclass : axi4lite_base_test


    // ----------------------------------------------------------------------
    // Smoke sequence: 2 writes, 2 reads, verify scoreboard sees them
    // ----------------------------------------------------------------------
    class axi4lite_smoke_seq extends uvm_sequence #(axi4lite_txn);

        `uvm_object_utils(axi4lite_smoke_seq)

        function new(string name = "axi4lite_smoke_seq");
            super.new(name);
        endfunction

        task body();
            axi4lite_txn t;

            // Write 0xDEADBEEF to addr 0x00
            t = axi4lite_txn::type_id::create("w0");
            start_item(t);
            assert(t.randomize() with { kind == AXI_WRITE; addr == 5'h00;
                                         data == 32'hDEAD_BEEF; strb == 4'hF; });
            finish_item(t);

            // Write 0xCAFEBABE to addr 0x04
            t = axi4lite_txn::type_id::create("w1");
            start_item(t);
            assert(t.randomize() with { kind == AXI_WRITE; addr == 5'h04;
                                         data == 32'hCAFE_BABE; strb == 4'hF; });
            finish_item(t);

            // Read 0x00, expect 0xDEADBEEF
            t = axi4lite_txn::type_id::create("r0");
            start_item(t);
            assert(t.randomize() with { kind == AXI_READ; addr == 5'h00; });
            finish_item(t);

            // Read 0x04, expect 0xCAFEBABE
            t = axi4lite_txn::type_id::create("r1");
            start_item(t);
            assert(t.randomize() with { kind == AXI_READ; addr == 5'h04; });
            finish_item(t);
        endtask

    endclass : axi4lite_smoke_seq


    // ----------------------------------------------------------------------
    // Smoke test: launches smoke sequence on the agent
    // ----------------------------------------------------------------------
    class axi4lite_smoke_test extends axi4lite_base_test;

        `uvm_component_utils(axi4lite_smoke_test)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        task run_phase(uvm_phase phase);
            axi4lite_smoke_seq seq;
            phase.raise_objection(this);
            seq = axi4lite_smoke_seq::type_id::create("seq");
            seq.start(env.agent.sqr);
            #200ns;
            phase.drop_objection(this);
        endtask

    endclass : axi4lite_smoke_test

endpackage : axi4lite_tests_pkg

`endif // AXI4LITE_TESTS_PKG_SV
