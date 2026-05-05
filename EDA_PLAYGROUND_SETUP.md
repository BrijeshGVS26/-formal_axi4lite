# EDA Playground Setup — AXI4-Lite UVM Smoke Test

## Step-by-step

1. Go to https://www.edaplayground.com/ and sign in.
2. Click **Examples → UVM 1.2 → Hello World** (or any UVM example) to start from a known-good UVM template.
3. Replace the contents of the **Design** pane with the contents of `design.sv`.
4. Replace the contents of the **Testbench + Verification** pane with the contents of `testbench.sv`.
5. In the right-hand panel:
   - **Tools & Simulators**: pick `Synopsys VCS 2023.03` (or any available — Aldec Riviera Pro and Mentor Questa also work).
   - **UVM/OVM**: select `UVM 1.2`.
   - **Run options**: add `+UVM_TESTNAME=axi4lite_smoke_test +UVM_VERBOSITY=UVM_MEDIUM`.
   - **Compile options**: leave default (`-timescale=1ns/1ps` is already implicit via the `\`timescale` in the file).
   - **Open EPWave after run**: ✅ check this so you get a waveform.
6. Click **Run**.

## What you should see

Console log includes:
- `UVM_INFO ... [SB] WRITE addr=0x00 data=0xDEADBEEF`
- `UVM_INFO ... [SB] WRITE addr=0x04 data=0xCAFEBABE`
- `UVM_INFO ... [SB] READ OK   addr=0x00 data=0xDEADBEEF`
- `UVM_INFO ... [SB] READ OK   addr=0x04 data=0xCAFEBABE`
- `UVM_INFO ... [SB] Summary: writes=2 reads=2 mismatches=0`
- `--- UVM Report Summary ---` with `UVM_ERROR : 0`

EPWave should show the AXI4-Lite handshakes for both writes and both reads.

## If it errors

- "Cannot find virtual interface": you forgot to set the simulator to one with UVM 1.2. Re-pick VCS/Aldec/Questa with UVM 1.2 explicitly selected.
- "Class not found `axi4lite_smoke_test`": the `+UVM_TESTNAME` argument is missing from Run options.
- Compile error on `'0`: bump simulator to a newer version (most current ones support SystemVerilog 2017).

## Save your work

Once it runs green:
- Click **Save** (top right) to get a permanent URL like `https://www.edaplayground.com/x/abcd`.
- This URL is what you'll drop into your LinkedIn post and resume — anyone can click "Run" and reproduce.
