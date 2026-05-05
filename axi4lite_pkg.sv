// =============================================================================
// axi4lite_pkg.sv
// UVM agent for AXI4-Lite: transaction, sequencer, driver, monitor, agent.
// =============================================================================
`ifndef AXI4LITE_PKG_SV
`define AXI4LITE_PKG_SV

package axi4lite_pkg;

    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // ----------------------------------------------------------------------
    // Transaction
    // ----------------------------------------------------------------------
    typedef enum bit { AXI_READ = 1'b0, AXI_WRITE = 1'b1 } axi_kind_e;

    class axi4lite_txn extends uvm_sequence_item;

        rand axi_kind_e kind;
        rand bit [4:0]  addr;
        rand bit [31:0] data;     // write data (input) / read data (output)
        rand bit [3:0]  strb;
             bit [1:0]  resp;     // captured response

        // Force word-aligned addresses (bottom 2 bits = 0)
        constraint c_addr_aligned { addr[1:0] == 2'b00; }
        constraint c_strb_default { soft strb == 4'hF; }

        `uvm_object_utils_begin(axi4lite_txn)
            `uvm_field_enum(axi_kind_e, kind, UVM_ALL_ON)
            `uvm_field_int (addr, UVM_ALL_ON)
            `uvm_field_int (data, UVM_ALL_ON)
            `uvm_field_int (strb, UVM_ALL_ON)
            `uvm_field_int (resp, UVM_ALL_ON)
        `uvm_object_utils_end

        function new(string name = "axi4lite_txn");
            super.new(name);
        endfunction

    endclass : axi4lite_txn


    // ----------------------------------------------------------------------
    // Sequencer (typedef)
    // ----------------------------------------------------------------------
    typedef uvm_sequencer #(axi4lite_txn) axi4lite_sequencer;


    // ----------------------------------------------------------------------
    // Driver
    //   Drives a single AXI4-Lite transaction at a time.
    //   For WRITE: drives AW, then W, waits for B.
    //   For READ : drives AR, waits for R.
    // ----------------------------------------------------------------------
    class axi4lite_driver extends uvm_driver #(axi4lite_txn);

        virtual axi4lite_if vif;

        `uvm_component_utils(axi4lite_driver)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual axi4lite_if)::get(this, "", "vif", vif))
                `uvm_fatal("DRV", "No virtual interface set for axi4lite_driver")
        endfunction

        task run_phase(uvm_phase phase);
            // Idle all master-driven signals
            vif.awvalid <= 1'b0;
            vif.wvalid  <= 1'b0;
            vif.bready  <= 1'b0;
            vif.arvalid <= 1'b0;
            vif.rready  <= 1'b0;

            // Wait for reset deassertion
            @(posedge vif.aclk);
            wait (vif.aresetn === 1'b1);

            forever begin
                axi4lite_txn req;
                seq_item_port.get_next_item(req);
                if (req.kind == AXI_WRITE) drive_write(req);
                else                       drive_read(req);
                seq_item_port.item_done();
            end
        endtask

        task drive_write(axi4lite_txn t);
            // Drive AW and W concurrently (allowed by AXI4-Lite)
            @(posedge vif.aclk);
            vif.awaddr  <= t.addr;
            vif.awvalid <= 1'b1;
            vif.wdata   <= t.data;
            vif.wstrb   <= t.strb;
            vif.wvalid  <= 1'b1;
            vif.bready  <= 1'b1;

            // Wait for AWREADY
            do @(posedge vif.aclk); while (!vif.awready);
            vif.awvalid <= 1'b0;

            // Wait for WREADY (may already be asserted)
            while (!vif.wready) @(posedge vif.aclk);
            vif.wvalid  <= 1'b0;

            // Wait for BVALID
            while (!vif.bvalid) @(posedge vif.aclk);
            t.resp = vif.bresp;
            @(posedge vif.aclk);
            vif.bready <= 1'b0;
        endtask

        task drive_read(axi4lite_txn t);
            @(posedge vif.aclk);
            vif.araddr  <= t.addr;
            vif.arvalid <= 1'b1;
            vif.rready  <= 1'b1;

            do @(posedge vif.aclk); while (!vif.arready);
            vif.arvalid <= 1'b0;

            while (!vif.rvalid) @(posedge vif.aclk);
            t.data = vif.rdata;
            t.resp = vif.rresp;
            @(posedge vif.aclk);
            vif.rready <= 1'b0;
        endtask

    endclass : axi4lite_driver


    // ----------------------------------------------------------------------
    // Monitor
    //   Snoops completed transactions and broadcasts on analysis port.
    // ----------------------------------------------------------------------
    class axi4lite_monitor extends uvm_monitor;

        virtual axi4lite_if vif;
        uvm_analysis_port #(axi4lite_txn) ap;

        `uvm_component_utils(axi4lite_monitor)

        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap = new("ap", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db#(virtual axi4lite_if)::get(this, "", "vif", vif))
                `uvm_fatal("MON", "No virtual interface set for axi4lite_monitor")
        endfunction

        task run_phase(uvm_phase phase);
            fork
                monitor_writes();
                monitor_reads();
            join
        endtask

        // Capture a write transaction: AW handshake, W handshake, B handshake
        task monitor_writes();
            forever begin
                axi4lite_txn t = axi4lite_txn::type_id::create("wr_txn");
                t.kind = AXI_WRITE;

                // AW handshake
                do @(posedge vif.aclk); while (!(vif.awvalid && vif.awready));
                t.addr = vif.awaddr;

                // W handshake (may be same cycle or after)
                while (!(vif.wvalid && vif.wready)) @(posedge vif.aclk);
                t.data = vif.wdata;
                t.strb = vif.wstrb;

                // B handshake
                while (!(vif.bvalid && vif.bready)) @(posedge vif.aclk);
                t.resp = vif.bresp;

                ap.write(t);
            end
        endtask

        // Capture a read transaction: AR handshake, R handshake
        task monitor_reads();
            forever begin
                axi4lite_txn t = axi4lite_txn::type_id::create("rd_txn");
                t.kind = AXI_READ;

                do @(posedge vif.aclk); while (!(vif.arvalid && vif.arready));
                t.addr = vif.araddr;

                while (!(vif.rvalid && vif.rready)) @(posedge vif.aclk);
                t.data = vif.rdata;
                t.resp = vif.rresp;

                ap.write(t);
            end
        endtask

    endclass : axi4lite_monitor


    // ----------------------------------------------------------------------
    // Agent
    // ----------------------------------------------------------------------
    class axi4lite_agent extends uvm_agent;

        axi4lite_sequencer sqr;
        axi4lite_driver    drv;
        axi4lite_monitor   mon;

        `uvm_component_utils(axi4lite_agent)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

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

    endclass : axi4lite_agent

endpackage : axi4lite_pkg

`endif // AXI4LITE_PKG_SV
