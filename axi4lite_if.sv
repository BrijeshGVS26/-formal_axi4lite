// =============================================================================
// axi4lite_if.sv
// AXI4-Lite SystemVerilog interface used by the UVM agent and DUT.
// Parameters mirror the slave RTL (ADDR_WIDTH=5, DATA_WIDTH=32).
// =============================================================================
`ifndef AXI4LITE_IF_SV
`define AXI4LITE_IF_SV

interface axi4lite_if #(
    parameter int ADDR_WIDTH = 5,
    parameter int DATA_WIDTH = 32
) (
    input logic aclk,
    input logic aresetn
);

    // Write address channel
    logic [ADDR_WIDTH-1:0]   awaddr;
    logic                    awvalid;
    logic                    awready;

    // Write data channel
    logic [DATA_WIDTH-1:0]   wdata;
    logic [DATA_WIDTH/8-1:0] wstrb;
    logic                    wvalid;
    logic                    wready;

    // Write response channel
    logic [1:0]              bresp;
    logic                    bvalid;
    logic                    bready;

    // Read address channel
    logic [ADDR_WIDTH-1:0]   araddr;
    logic                    arvalid;
    logic                    arready;

    // Read data channel
    logic [DATA_WIDTH-1:0]   rdata;
    logic [1:0]              rresp;
    logic                    rvalid;
    logic                    rready;

    // Master modport (driven by UVM driver)
    modport master (
        input  aclk, aresetn,
        output awaddr, awvalid, wdata, wstrb, wvalid, bready,
        output araddr, arvalid, rready,
        input  awready, wready, bresp, bvalid,
        input  arready, rdata, rresp, rvalid
    );

    // Monitor modport (read-only snooping)
    modport monitor (
        input  aclk, aresetn,
        input  awaddr, awvalid, awready,
        input  wdata, wstrb, wvalid, wready,
        input  bresp, bvalid, bready,
        input  araddr, arvalid, arready,
        input  rdata, rresp, rvalid, rready
    );

endinterface : axi4lite_if

`endif // AXI4LITE_IF_SV
