# Day 2 — Run the RAL Tests

## What's new in this `testbench.sv`

Added on top of Day 1:
- **`axi4lite_ral_pkg`** — RAL register block with 8 named CSRs (CTRL, STATUS, INT_EN, INT_STAT, SCRATCH0–3) at offsets 0x00–0x1C, plus an `axi4lite_reg_adapter` that converts `uvm_reg_bus_op` ↔ `axi4lite_txn`.
- **`uvm_reg_predictor`** wired to the monitor's analysis port — keeps the RAL mirror in sync with the actual bus traffic.
- **Three new tests** wrapping built-in UVM RAL sequences:
  - `axi4lite_reg_hw_reset_test` — runs `uvm_reg_hw_reset_seq` (verifies reset values)
  - `axi4lite_reg_bit_bash_test` — runs `uvm_reg_bit_bash_seq` (walks 1 through every bit)
  - `axi4lite_reg_access_test` — runs `uvm_reg_access_seq` (write/read each register)

## How to run each test

In the EDA Playground **Run Options** field, change `+UVM_TESTNAME=...` and click **Run**.
**Do not include `+access+r` — EDA Playground adds it for you.**

### 1. HW Reset test
```
+UVM_TESTNAME=axi4lite_reg_hw_reset_test +UVM_VERBOSITY=UVM_MEDIUM
```
Expect log lines like:
```
UVM_INFO ... [TEST] Starting uvm_reg_hw_reset_seq
UVM_INFO ... [uvm_reg_hw_reset_seq] Verifying reset value of register ...CTRL
UVM_INFO ... [uvm_reg_hw_reset_seq] Verifying reset value of register ...STATUS
... (8 registers)
UVM_ERROR :    0
UVM_FATAL :    0
```

### 2. Bit Bash test
```
+UVM_TESTNAME=axi4lite_reg_bit_bash_test +UVM_VERBOSITY=UVM_MEDIUM
```
Expect 8 registers × ~32 bit positions × write+read = ~512 bus transactions.

### 3. Access test
```
+UVM_TESTNAME=axi4lite_reg_access_test +UVM_VERBOSITY=UVM_MEDIUM
```
Expect 8 registers × write+read = 16 bus transactions.

### 4. (Optional) Original smoke test still works
```
+UVM_TESTNAME=axi4lite_smoke_test +UVM_VERBOSITY=UVM_MEDIUM
```

## What success looks like

Each test ends with:
```
UVM_ERROR :    0
UVM_FATAL :    0
```

If you see `UVM_ERROR > 0`, paste the log and we'll debug.

## What you've actually built (resume material)

> Extended a formal-verified AXI4-Lite slave with a full UVM environment and RAL register
> model. Modeled 8 CSRs (CTRL, STATUS, INT_EN, INT_STAT, SCRATCH0–3) in a `uvm_reg_block`,
> wrote a `uvm_reg_adapter` for AXI4-Lite, and connected a `uvm_reg_predictor` to keep the
> RAL mirror coherent with bus traffic. Verified with built-in `uvm_reg_hw_reset_seq`,
> `uvm_reg_bit_bash_seq`, and `uvm_reg_access_seq` — exercising reset values, per-bit
> read/write integrity, and full-register access for all 8 CSRs.

## Save 3 separate playgrounds

After each test runs green, click **Save** and capture the URL. You'll have three permanent
links — one per test. These go on your GitHub README and LinkedIn post.
