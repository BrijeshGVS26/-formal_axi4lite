// =============================================================================
// testbench.sv — paste into EDA Playground "Testbench + Verification" pane
// Day 2: full UVM env + RAL register model + AXI4-Lite adapter + predictor.
// Tests: smoke, reg_hw_reset, reg_bit_bash, reg_access.
// =============================================================================
`timescale 1ns/1ps

// ============================================================================
//  AXI4-Lite Interface
// ============================================================================
interface axi4lite_if #(
    parameter int ADDR_WIDTH = 5,
    parameter int DATA_WIDTH = 32
) (
    input logic aclk,
    input logic aresetn
);
    logic [ADDR_WIDTH-1:0]   awaddr;
    logic                    awvalid;
    logic                    awready;
    logic [DATA_WIDTH-1:0]   wdata;
    logic [DATA_WIDTH/8-1:0] wstrb;
    logic                    wvalid;
    logic                    wready;
    logic [1:0]              bresp;
    logic                    bvalid;
    logic                    bready;
    logic [ADDR_WIDTH-1:0]   araddr;
    logic                    arvalid;
    logic                    arready;
    logic [DATA_WIDTH-1:0]   rdata;
    logic [1:0]              rresp;
    logic                    rvalid;
    logic                    rready;
endinterface : axi4lite_if


// ============================================================================
//  Agent package: transaction, sequencer, driver, monitor, agent
// ============================================================================
package axi4lite_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    typedef enum bit { AXI_READ = 1'b0, AXI_WRITE = 1'b1 } axi_kind_e;

    class axi4lite_txn extends uvm_sequence_item;
        rand axi_kind_e kind;
        rand bit [4:0]  addr;
        rand bit [31:0] data;
        rand bit [3:0]  strb;
             bit [1:0]  resp;

        constraint c_addr_aligned { addr[1:0] == 2'b00; }
        constraint c_strb_default { soft strb == 4'hF; }

        `uvm_object_utils_begin(axi4lite_txn)
            `uvm_field_enum(axi_kind_e, kind, UVM_ALL_ON)
            `uvm_field_int (addr, UVM_ALL_ON)
            `uvm_field_int (data, UVM_ALL_ON)
            `uvm_field_int (strb, UVM_ALL_ON)
            `uvm_field_int (resp, UVM_ALL_ON)
        `uvm_object_utils_end

        function new(string name = "axi4lite_txn"); super.new(name); endfunction
    endclass

    typedef uvm_sequencer #(axi4lite_txn) axi4lite_sequencer;

    class axi4lite_driver extends uvm_driver #(axi4lite_txn);
        virtual axi4lite_if vif;
        `uvm_component_utils(axi4lite_driver)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual axi4lite_if)::get(this, "", "vif", vif))
                `uvm_fatal("DRV", "No virtual interface set")
        endfunction

        task run_phase(uvm_phase phase);
            vif.awvalid <= 1'b0; vif.wvalid  <= 1'b0; vif.bready <= 1'b0;
            vif.arvalid <= 1'b0; vif.rready  <= 1'b0;
            @(posedge vif.aclk);
            wait (vif.aresetn === 1'b1);
            forever begin
                axi4lite_txn req;
                seq_item_port.get_next_item(req);
                if (req.kind == AXI_WRITE) drive_write(req);
                else                       drive_read(req);
                // Pass `req` so the RAL adapter's bus2reg() gets the populated
                // transaction (read data + response). Without this, RAL reads hang.
                seq_item_port.item_done(req);
            end
        endtask

        task drive_write(axi4lite_txn t);
            @(posedge vif.aclk);
            vif.awaddr <= t.addr; vif.awvalid <= 1'b1;
            vif.wdata  <= t.data; vif.wstrb   <= t.strb; vif.wvalid <= 1'b1;
            vif.bready <= 1'b1;
            do @(posedge vif.aclk); while (!vif.awready);
            vif.awvalid <= 1'b0;
            while (!vif.wready) @(posedge vif.aclk);
            vif.wvalid <= 1'b0;
            while (!vif.bvalid) @(posedge vif.aclk);
            t.resp = vif.bresp;
            @(posedge vif.aclk);
            vif.bready <= 1'b0;
        endtask

        task drive_read(axi4lite_txn t);
            @(posedge vif.aclk);
            vif.araddr <= t.addr; vif.arvalid <= 1'b1; vif.rready <= 1'b1;
            do @(posedge vif.aclk); while (!vif.arready);
            vif.arvalid <= 1'b0;
            while (!vif.rvalid) @(posedge vif.aclk);
            t.data = vif.rdata; t.resp = vif.rresp;
            @(posedge vif.aclk);
            vif.rready <= 1'b0;
        endtask
    endclass

    class axi4lite_monitor extends uvm_monitor;
        virtual axi4lite_if vif;
        uvm_analysis_port #(axi4lite_txn) ap;
        `uvm_component_utils(axi4lite_monitor)

        function new(string name, uvm_component parent);
            super.new(name, parent); ap = new("ap", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual axi4lite_if)::get(this, "", "vif", vif))
                `uvm_fatal("MON", "No virtual interface set")
        endfunction

        task run_phase(uvm_phase phase);
            fork mon_writes(); mon_reads(); join
        endtask

        task mon_writes();
            forever begin
                axi4lite_txn t = axi4lite_txn::type_id::create("wr_txn");
                t.kind = AXI_WRITE;
                do @(posedge vif.aclk); while (!(vif.awvalid && vif.awready));
                t.addr = vif.awaddr;
                while (!(vif.wvalid && vif.wready)) @(posedge vif.aclk);
                t.data = vif.wdata; t.strb = vif.wstrb;
                while (!(vif.bvalid && vif.bready)) @(posedge vif.aclk);
                t.resp = vif.bresp;
                ap.write(t);
            end
        endtask

        task mon_reads();
            forever begin
                axi4lite_txn t = axi4lite_txn::type_id::create("rd_txn");
                t.kind = AXI_READ;
                do @(posedge vif.aclk); while (!(vif.arvalid && vif.arready));
                t.addr = vif.araddr;
                while (!(vif.rvalid && vif.rready)) @(posedge vif.aclk);
                t.data = vif.rdata; t.resp = vif.rresp;
                ap.write(t);
            end
        endtask
    endclass

    class axi4lite_agent extends uvm_agent;
        axi4lite_sequencer sqr;
        axi4lite_driver    drv;
        axi4lite_monitor   mon;
        `uvm_component_utils(axi4lite_agent)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            mon = axi4lite_monitor::type_id::create("mon", this);
            if (get_is_active() == UVM_ACTIVE) begin
                sqr = axi4lite_sequencer::type_id::create("sqr", this);
                drv = axi4lite_driver   ::type_id::create("drv", this);
            end
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);
            if (get_is_active() == UVM_ACTIVE)
                drv.seq_item_port.connect(sqr.seq_item_export);
        endfunction
    endclass
endpackage : axi4lite_pkg


// ============================================================================
//  RAL package: register class, register block, AXI4-Lite adapter
// ============================================================================
package axi4lite_ral_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import axi4lite_pkg::*;

    // --------------------------------------------------------------------
    // Generic 32-bit RW register (one full-width field, reset = 0)
    // --------------------------------------------------------------------
    class axi_rw32_reg extends uvm_reg;
        rand uvm_reg_field val;

        `uvm_object_utils(axi_rw32_reg)

        function new(string name = "axi_rw32_reg");
            super.new(name, 32, UVM_NO_COVERAGE);
        endfunction

        virtual function void build();
            val = uvm_reg_field::type_id::create("val");
            // configure(parent, size, lsb_pos, access, volatile, reset,
            //           has_reset, is_rand, individually_accessible)
            val.configure(this, 32, 0, "RW", 0, 32'h0000_0000, 1, 1, 1);
        endfunction
    endclass

    // --------------------------------------------------------------------
    // Register block: 8 CSRs at 0x00..0x1C
    // --------------------------------------------------------------------
    class axi4lite_reg_block extends uvm_reg_block;
        rand axi_rw32_reg CTRL;
        rand axi_rw32_reg STATUS;
        rand axi_rw32_reg INT_EN;
        rand axi_rw32_reg INT_STAT;
        rand axi_rw32_reg SCRATCH0;
        rand axi_rw32_reg SCRATCH1;
        rand axi_rw32_reg SCRATCH2;
        rand axi_rw32_reg SCRATCH3;

        `uvm_object_utils(axi4lite_reg_block)

        function new(string name = "axi4lite_reg_block");
            super.new(name, UVM_NO_COVERAGE);
        endfunction

        virtual function void build();
            CTRL     = axi_rw32_reg::type_id::create("CTRL");
            CTRL.configure(this, null, ""); CTRL.build();
            STATUS   = axi_rw32_reg::type_id::create("STATUS");
            STATUS.configure(this, null, ""); STATUS.build();
            INT_EN   = axi_rw32_reg::type_id::create("INT_EN");
            INT_EN.configure(this, null, ""); INT_EN.build();
            INT_STAT = axi_rw32_reg::type_id::create("INT_STAT");
            INT_STAT.configure(this, null, ""); INT_STAT.build();
            SCRATCH0 = axi_rw32_reg::type_id::create("SCRATCH0");
            SCRATCH0.configure(this, null, ""); SCRATCH0.build();
            SCRATCH1 = axi_rw32_reg::type_id::create("SCRATCH1");
            SCRATCH1.configure(this, null, ""); SCRATCH1.build();
            SCRATCH2 = axi_rw32_reg::type_id::create("SCRATCH2");
            SCRATCH2.configure(this, null, ""); SCRATCH2.build();
            SCRATCH3 = axi_rw32_reg::type_id::create("SCRATCH3");
            SCRATCH3.configure(this, null, ""); SCRATCH3.build();

            // create_map(name, base_addr, n_bytes, endian, byte_addressing)
            default_map = create_map("default_map", 'h00, 4, UVM_LITTLE_ENDIAN, 1);
            default_map.add_reg(CTRL,     'h00, "RW");
            default_map.add_reg(STATUS,   'h04, "RW");
            default_map.add_reg(INT_EN,   'h08, "RW");
            default_map.add_reg(INT_STAT, 'h0C, "RW");
            default_map.add_reg(SCRATCH0, 'h10, "RW");
            default_map.add_reg(SCRATCH1, 'h14, "RW");
            default_map.add_reg(SCRATCH2, 'h18, "RW");
            default_map.add_reg(SCRATCH3, 'h1C, "RW");

            lock_model();
        endfunction
    endclass

    // --------------------------------------------------------------------
    // AXI4-Lite reg adapter:
    //   reg2bus → uvm_reg_bus_op  ➜  axi4lite_txn
    //   bus2reg → axi4lite_txn    ➜  uvm_reg_bus_op
    // --------------------------------------------------------------------
    class axi4lite_reg_adapter extends uvm_reg_adapter;
        `uvm_object_utils(axi4lite_reg_adapter)

        function new(string name = "axi4lite_reg_adapter");
            super.new(name);
            provides_responses = 1; // adapter forwards bus response back to RAL
        endfunction

        virtual function uvm_sequence_item reg2bus(const ref uvm_reg_bus_op rw);
            axi4lite_txn t = axi4lite_txn::type_id::create("ral_bus_txn");
            t.kind = (rw.kind == UVM_READ) ? AXI_READ : AXI_WRITE;
            t.addr = rw.addr[4:0];
            t.data = rw.data[31:0];
            t.strb = 4'hF;
            return t;
        endfunction

        virtual function void bus2reg(uvm_sequence_item bus_item,
                                       ref uvm_reg_bus_op rw);
            axi4lite_txn t;
            if (!$cast(t, bus_item))
                `uvm_fatal("ADAPT", "Bus item is not axi4lite_txn")
            rw.kind   = (t.kind == AXI_READ) ? UVM_READ : UVM_WRITE;
            rw.addr   = t.addr;
            rw.data   = t.data;
            rw.status = (t.resp == 2'b00) ? UVM_IS_OK : UVM_NOT_OK;
        endfunction
    endclass

endpackage : axi4lite_ral_pkg


// ============================================================================
//  Env package: scoreboard + env (now with regmodel + predictor + adapter)
// ============================================================================
package axi4lite_env_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import axi4lite_pkg::*;
    import axi4lite_ral_pkg::*;

    class axi4lite_scoreboard extends uvm_subscriber #(axi4lite_txn);
        `uvm_component_utils(axi4lite_scoreboard)
        bit [31:0]   shadow_mem [bit [2:0]];
        int unsigned n_writes, n_reads, n_mismatches;

        function new(string name, uvm_component parent); super.new(name, parent); endfunction

        function void write(axi4lite_txn t);
            bit [2:0] idx = t.addr[4:2];
            if (t.kind == AXI_WRITE) begin
                shadow_mem[idx] = t.data;
                n_writes++;
                `uvm_info("SB", $sformatf("WRITE addr=0x%02h data=0x%08h", t.addr, t.data), UVM_HIGH)
            end else begin
                n_reads++;
                if (shadow_mem.exists(idx)) begin
                    bit [31:0] exp = shadow_mem[idx];
                    if (t.data !== exp) begin
                        n_mismatches++;
                        `uvm_error("SB", $sformatf("READ MISMATCH addr=0x%02h got=0x%08h exp=0x%08h",
                                   t.addr, t.data, exp))
                    end else begin
                        `uvm_info("SB", $sformatf("READ OK   addr=0x%02h data=0x%08h",
                                   t.addr, t.data), UVM_HIGH)
                    end
                end
            end
        endfunction

        function void report_phase(uvm_phase phase);
            `uvm_info("SB", $sformatf("Summary: writes=%0d reads=%0d mismatches=%0d",
                       n_writes, n_reads, n_mismatches), UVM_NONE)
            if (n_mismatches != 0) `uvm_error("SB", "Test failed: read mismatches detected")
        endfunction
    endclass

    class axi4lite_env extends uvm_env;
        axi4lite_agent                    agent;
        axi4lite_scoreboard               sb;
        axi4lite_reg_block                regmodel;
        axi4lite_reg_adapter              adapter;
        uvm_reg_predictor #(axi4lite_txn) predictor;

        `uvm_component_utils(axi4lite_env)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            agent     = axi4lite_agent     ::type_id::create("agent", this);
            sb        = axi4lite_scoreboard::type_id::create("sb",    this);

            regmodel  = axi4lite_reg_block ::type_id::create("regmodel");
            regmodel.build();

            adapter   = axi4lite_reg_adapter::type_id::create("adapter");
            predictor = uvm_reg_predictor #(axi4lite_txn)::type_id::create("predictor", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            super.connect_phase(phase);

            // Monitor → Scoreboard (read/write checking)
            agent.mon.ap.connect(sb.analysis_export);

            // Bind RAL map to the agent's sequencer via the adapter
            regmodel.default_map.set_sequencer(agent.sqr, adapter);
            // Disable auto-predict so the explicit predictor handles RAL mirror updates
            regmodel.default_map.set_auto_predict(0);

            // Monitor → Predictor → RAL mirror
            predictor.map     = regmodel.default_map;
            predictor.adapter = adapter;
            agent.mon.ap.connect(predictor.bus_in);
        endfunction
    endclass
endpackage : axi4lite_env_pkg


// ============================================================================
//  Tests package: base + smoke + RAL hw_reset / bit_bash / access
// ============================================================================
package axi4lite_tests_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import axi4lite_pkg::*;
    import axi4lite_ral_pkg::*;
    import axi4lite_env_pkg::*;

    // --------------------------------------------------------------------
    // Base test
    // --------------------------------------------------------------------
    class axi4lite_base_test extends uvm_test;
        axi4lite_env env;
        `uvm_component_utils(axi4lite_base_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = axi4lite_env::type_id::create("env", this);
        endfunction

        function void end_of_elaboration_phase(uvm_phase phase);
            uvm_top.print_topology();
        endfunction
    endclass


    // --------------------------------------------------------------------
    // Smoke test (Day 1 — direct bus traffic, not via RAL)
    // --------------------------------------------------------------------
    class axi4lite_smoke_seq extends uvm_sequence #(axi4lite_txn);
        `uvm_object_utils(axi4lite_smoke_seq)
        function new(string name = "axi4lite_smoke_seq"); super.new(name); endfunction

        task body();
            axi4lite_txn t;
            t = axi4lite_txn::type_id::create("w0");
            start_item(t);
            assert(t.randomize() with { kind == AXI_WRITE; addr == 5'h00;
                                         data == 32'hDEAD_BEEF; strb == 4'hF; });
            finish_item(t);

            t = axi4lite_txn::type_id::create("w1");
            start_item(t);
            assert(t.randomize() with { kind == AXI_WRITE; addr == 5'h04;
                                         data == 32'hCAFE_BABE; strb == 4'hF; });
            finish_item(t);

            t = axi4lite_txn::type_id::create("r0");
            start_item(t);
            assert(t.randomize() with { kind == AXI_READ; addr == 5'h00; });
            finish_item(t);

            t = axi4lite_txn::type_id::create("r1");
            start_item(t);
            assert(t.randomize() with { kind == AXI_READ; addr == 5'h04; });
            finish_item(t);
        endtask
    endclass

    class axi4lite_smoke_test extends axi4lite_base_test;
        `uvm_component_utils(axi4lite_smoke_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction

        task run_phase(uvm_phase phase);
            axi4lite_smoke_seq seq;
            phase.raise_objection(this);
            seq = axi4lite_smoke_seq::type_id::create("seq");
            seq.start(env.agent.sqr);
            #200ns;
            phase.drop_objection(this);
        endtask
    endclass


    // --------------------------------------------------------------------
    // RAL HW Reset test
    //   Reads every register and verifies it equals its configured reset value.
    // --------------------------------------------------------------------
    class axi4lite_reg_hw_reset_test extends axi4lite_base_test;
        `uvm_component_utils(axi4lite_reg_hw_reset_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction

        task run_phase(uvm_phase phase);
            uvm_reg_hw_reset_seq seq;
            phase.raise_objection(this);
            `uvm_info("TEST", "Starting uvm_reg_hw_reset_seq", UVM_LOW)
            seq = uvm_reg_hw_reset_seq::type_id::create("seq");
            seq.model = env.regmodel;
            seq.start(null);
            #200ns;
            phase.drop_objection(this);
        endtask
    endclass


    // --------------------------------------------------------------------
    // RAL Bit Bash test
    //   Walks a 1 through every bit position of every register and checks
    //   the read-back value matches the access policy.
    // --------------------------------------------------------------------
    class axi4lite_reg_bit_bash_test extends axi4lite_base_test;
        `uvm_component_utils(axi4lite_reg_bit_bash_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction

        task run_phase(uvm_phase phase);
            uvm_reg_bit_bash_seq seq;
            phase.raise_objection(this);
            `uvm_info("TEST", "Starting uvm_reg_bit_bash_seq", UVM_LOW)
            seq = uvm_reg_bit_bash_seq::type_id::create("seq");
            seq.model = env.regmodel;
            seq.start(null);
            #200ns;
            phase.drop_objection(this);
        endtask
    endclass


    // --------------------------------------------------------------------
    // Custom front-door-only access sequence
    //   The library's uvm_reg_access_seq requires an HDL backdoor for the
    //   bus-vs-backdoor consistency check. When no backdoor is configured
    //   (typical for memory-backed register files), it silently skips every
    //   register. This custom seq performs front-door-only write-then-read
    //   on every register in the model and self-checks via the RAL mirror.
    // --------------------------------------------------------------------
    class axi4lite_reg_frontdoor_access_seq
            extends uvm_reg_sequence #(uvm_sequence #(uvm_reg_item));

        `uvm_object_utils(axi4lite_reg_frontdoor_access_seq)

        function new(string name = "axi4lite_reg_frontdoor_access_seq");
            super.new(name);
        endfunction

        task body();
            uvm_reg        regs[$];
            uvm_status_e   status;
            uvm_reg_data_t wr_data, rd_data;

            if (model == null)
                `uvm_fatal("FRONTDOOR_ACCESS", "regmodel handle is null")

            model.get_registers(regs, UVM_HIER);
            `uvm_info("FRONTDOOR_ACCESS",
                      $sformatf("Front-door access on %0d registers", regs.size()),
                      UVM_LOW)

            foreach (regs[i]) begin
                wr_data = { $urandom(), $urandom() }; // 64-bit ok; lower 32 used
                regs[i].write(status, wr_data, UVM_FRONTDOOR);
                if (status != UVM_IS_OK)
                    `uvm_error("FRONTDOOR_ACCESS",
                        $sformatf("WRITE status=%s on %s",
                                  status.name(), regs[i].get_full_name()))

                regs[i].read(status, rd_data, UVM_FRONTDOOR);
                if (status != UVM_IS_OK)
                    `uvm_error("FRONTDOOR_ACCESS",
                        $sformatf("READ  status=%s on %s",
                                  status.name(), regs[i].get_full_name()))

                if (rd_data[31:0] !== wr_data[31:0]) begin
                    `uvm_error("FRONTDOOR_ACCESS",
                        $sformatf("MISMATCH %s wrote=0x%08h read=0x%08h",
                                  regs[i].get_full_name(),
                                  wr_data[31:0], rd_data[31:0]))
                end else begin
                    `uvm_info("FRONTDOOR_ACCESS",
                        $sformatf("OK %s = 0x%08h",
                                  regs[i].get_full_name(), rd_data[31:0]),
                        UVM_LOW)
                end
            end
        endtask
    endclass


    // --------------------------------------------------------------------
    // RAL Access test
    //   Uses the custom front-door access sequence above (since the slave
    //   is memory-backed and has no HDL backdoor).
    // --------------------------------------------------------------------
    class axi4lite_reg_access_test extends axi4lite_base_test;
        `uvm_component_utils(axi4lite_reg_access_test)
        function new(string name, uvm_component parent); super.new(name, parent); endfunction

        task run_phase(uvm_phase phase);
            axi4lite_reg_frontdoor_access_seq seq;
            phase.raise_objection(this);
            `uvm_info("TEST", "Starting axi4lite_reg_frontdoor_access_seq", UVM_LOW)
            seq = axi4lite_reg_frontdoor_access_seq::type_id::create("seq");
            seq.model = env.regmodel;
            seq.start(null);
            #200ns;
            phase.drop_objection(this);
        endtask
    endclass

endpackage : axi4lite_tests_pkg


// ============================================================================
//  TB top
// ============================================================================
module tb_top;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import axi4lite_pkg::*;
    import axi4lite_ral_pkg::*;
    import axi4lite_env_pkg::*;
    import axi4lite_tests_pkg::*;

    logic aclk    = 1'b0;
    logic aresetn = 1'b0;
    always #5 aclk = ~aclk;
    initial begin
        aresetn = 1'b0;
        repeat (5) @(posedge aclk);
        aresetn = 1'b1;
    end

    axi4lite_if #(.ADDR_WIDTH(5), .DATA_WIDTH(32)) vif (.aclk(aclk), .aresetn(aresetn));

    wire [1:0]  unused_w_state, unused_r_state;
    wire [4:0]  unused_waddr_q, unused_raddr_q;
    wire [31:0] unused_mem_at_watch;

    axi4lite_slave #(.ADDR_WIDTH(5), .DATA_WIDTH(32)) dut (
        .aclk(aclk), .aresetn(aresetn),
        .awaddr(vif.awaddr), .awvalid(vif.awvalid), .awready(vif.awready),
        .wdata(vif.wdata),   .wstrb(vif.wstrb),     .wvalid(vif.wvalid),  .wready(vif.wready),
        .bresp(vif.bresp),   .bvalid(vif.bvalid),   .bready(vif.bready),
        .araddr(vif.araddr), .arvalid(vif.arvalid), .arready(vif.arready),
        .rdata(vif.rdata),   .rresp(vif.rresp),     .rvalid(vif.rvalid),  .rready(vif.rready),
        .fv_w_state(unused_w_state), .fv_r_state(unused_r_state),
        .fv_waddr_q(unused_waddr_q), .fv_raddr_q(unused_raddr_q),
        .fv_watch_idx(3'b000), .fv_mem_at_watch(unused_mem_at_watch)
    );

    initial begin
        uvm_config_db#(virtual axi4lite_if)::set(null, "*", "vif", vif);
        $dumpfile("dump.vcd");
        $dumpvars(0, tb_top);
        run_test();
    end
endmodule
