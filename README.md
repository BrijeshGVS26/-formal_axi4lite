# AXI4-Lite slave verification: formal + UVM RAL

Portfolio project. I wanted to actually try formal property
verification (not just read about it), so I wrote a tiny AXI4-Lite
slave and checked 15 SystemVerilog assertions on it using SymbiYosys
and Z3. Then I dropped one bug into a copy of the slave to see what
catching a real violation looks like.

After that I extended the same DUT with a full UVM 1.2 environment
and a RAL register model — agent, scoreboard, `uvm_reg_predictor`,
a custom AXI4-Lite `uvm_reg_adapter`, eight named CSRs, and four
tests including three RAL sequences (reset value check, bit bash,
custom front-door access). Runs end-to-end on EDA Playground.

Free tools throughout. The formal flow runs on a Mac with no EDA
licence. The UVM flow runs in a browser via EDA Playground (Aldec
Riviera-PRO EDU + UVM 1.2).

## What's in this repo

```
formal_axi4lite/
  rtl/
    axi4lite_slave.sv          # the golden slave
    axi4lite_slave_buggy.sv    # same slave, one bug injected on purpose
  fv/
    axi4lite_fv_top.sv         # formal top: assumes + 15 assertions + scoreboard
    prove.sby                  # sby config for the golden design
    prove_buggy.sby            # sby config for the buggy design
  uvm/
    tb/
      axi4lite_if.sv           # AXI4-Lite SV interface
      tb_top.sv                # clk/reset, DUT, run_test()
    agent/
      axi4lite_pkg.sv          # txn, sequencer, driver, monitor, agent
    env/
      axi4lite_env_pkg.sv      # scoreboard + env (with regmodel + predictor)
    ral/                       # (RAL block + adapter live inside testbench.sv for now)
    tests/
      axi4lite_tests_pkg.sv    # base + smoke + 3 RAL tests
    sim/
      design.sv                # slave RTL for EDA Playground (Design pane)
      testbench.sv             # everything else for EDA Playground (Testbench pane)
      EDA_PLAYGROUND_SETUP.md  # click-by-click setup
      DAY2_RAL_INSTRUCTIONS.md # how to run each of the 4 tests
  docs/
    bugs_found.md              # walkthrough of the injected formal bug
    interview_prep.md          # Q&A I expect in a formal interview
    buggy_trace.png            # Surfer screenshot of the counterexample
  README.md
```

## Tools

- Yosys -- elaborates the SystemVerilog
- SymbiYosys (sby) -- front-end driver
- Z3 -- SMT backend that actually does the proving

All three install with Homebrew. On Apple Silicon some of them can be
annoying; the pre-built OSS CAD Suite tarball from the YosysHQ GitHub
releases page worked fine as a fallback.

Viewing VCDs on modern macOS was the most annoying part. The Homebrew
GTKWave cask ships a 32-bit binary macOS 14+ refuses to launch, and
the Perl wrapper it uses needs `Switch.pm` which isn't in core Perl
anymore (had to `sudo cpan -i Switch` and accept a bunch of config
defaults). Even after that the `gtkwave-bin` still wouldn't start
because of the macOS version check. I gave up and switched to Surfer
(`brew install surfer`) which just worked on the first try.

## How to run

```bash
# golden design -- 15/15 should pass
sby -f fv/prove.sby

# buggy design -- should fail on a01
sby -f fv/prove_buggy.sby
```

sby makes a workdir next to the .sby file. Counterexample traces land
at `fv/<taskdir>/engine_0/trace.vcd`.

## What got proven

Golden, `bmc: depth 20`:

```
[bmc] DONE (PASS, rc=0)   -- 15/15 assertions hold, ~28 s
[cvr] DONE (PASS, rc=0)   -- 3/3 cover points reached (steps 2, 4, 4)
```

Buggy, `bmc: depth 12`:

```
[bmc] DONE (FAIL, rc=2)  -- a01 (BVALID stability) violated at step 5
```

The injected bug drops `BVALID` in W_RESP without waiting for `BREADY`.
AXI4-Lite requires VALID to stay high until READY, so this is a direct
protocol violation. Solver found it in under a second.

The 15 assertions cover:

- VALID/READY stability (VALID must stay high until its READY)
- reset behaviour (BVALID/RVALID low during reset, no spurious pulses on reset-release)
- legal BRESP/RRESP encodings
- bounded-wait latency -- if the FSM is in its response state, the response signal has to already be valid
- read-after-write data integrity: an `anyconst` watch address + a
  scoreboard that mirrors `wdata`, compared against `rdata` when that
  address is read back

## UVM RAL verification

After the formal work I wanted the same DUT verified through a
realistic UVM environment too -- partly because a DV interview will
ask about UVM long before it asks about formal, and partly because
RAL is the one thing every SoC verification team uses that I'd never
actually built from scratch.

Built and verified on EDA Playground (Aldec Riviera-PRO EDU + UVM
1.2). One playground, four tests, swap `+UVM_TESTNAME` to switch:

- EDA Playground: **<paste your saved URL here>**

### What's in the env

`uvm/sim/testbench.sv` is one EDA-Playground-friendly concatenation
of:

- **`axi4lite_if`** -- bundles all 16 AXI4-Lite signals
- **`axi4lite_pkg`** -- agent: transaction (with `kind`, `addr`,
  `data`, `strb`, `resp`), driver, monitor (forks separate
  write-channel and read-channel processes), agent
- **`axi4lite_ral_pkg`** -- a generic 32-bit RW register class, the
  `axi4lite_reg_block` with 8 named CSRs (CTRL, STATUS, INT_EN,
  INT_STAT, SCRATCH0..3) at offsets 0x00..0x1C, and the custom
  `axi4lite_reg_adapter` (`reg2bus` / `bus2reg`)
- **`axi4lite_env_pkg`** -- env: agent + scoreboard +
  `uvm_reg_predictor` for explicit prediction, with the monitor's
  analysis port wired to both the SB and the predictor
- **`axi4lite_tests_pkg`** -- base test + smoke test + three RAL
  tests + a custom front-door access sequence

### Tests and results

| Test | `+UVM_TESTNAME` | Bus transactions | Result |
|---|---|---|---|
| Smoke (write/read sanity) | `axi4lite_smoke_test` | 4 | 0 mismatches |
| RAL reset-value check | `axi4lite_reg_hw_reset_test` | 8 reads | 0 mismatches |
| RAL bit bash | `axi4lite_reg_bit_bash_test` | 1,024 (512 W + 512 R) | 0 mismatches |
| RAL front-door access | `axi4lite_reg_access_test` | 16 (8 W + 8 R) | 0 mismatches |

Total: ~1,056 bus transactions across 8 registers, zero failures.

### The custom front-door access sequence

The library `uvm_reg_access_seq` requires an HDL backdoor for the
bus-vs-backdoor consistency check. When no backdoor is configured
(typical for memory-backed register files like this slave), it
silently skips every register -- my first run gave me 8
`UVM_WARNING`s and zero traffic. Rather than wire up an HDL path
just to satisfy the seq, I wrote `axi4lite_reg_frontdoor_access_seq`
that does what the bus path of `uvm_reg_access_seq` does without the
backdoor side: random pattern write to every register via
`UVM_FRONTDOOR`, read back, compare, log OK or MISMATCH.

### Things I got stuck on (UVM side)

- **First RAL run hung on the very first read.** I'd written the
  driver with `seq_item_port.item_done()` (no argument). For the
  smoke sequence that was fine -- the smoke seq doesn't read the
  response. But RAL pulls read data back through the response path:
  the adapter's `bus2reg()` is called on whatever the driver returns
  on `item_done`. With no argument, the response is null and the seq
  hangs forever waiting. EDA Playground killed the run with exit
  code 137 after the runtime cap. Fix: `item_done(req)` so the
  populated transaction (with `vif.rdata` already captured) flows
  back to the adapter.
- **`uvm_reg_access_seq` skipping** -- see the section above.
- **`+access+r` doubling itself.** EDA Playground auto-prepends
  `+access+r` to the runtime args. I left it in my Run Options too
  and got `+access+r+access+r` which Aldec rejected with `Incorrect
  syntax`. Removing it from Run Options fixed it.
- **Compile warning on `default: w_state <= W_IDLE;`.** Riviera
  flagged it as a duplicate-case-item warning because `'0` is the
  same as `W_IDLE = 2'b00`. Harmless -- left it in.

## Things I got stuck on

I didn't really understand k-induction properly when I started. My
first version of the bounded-wait property used an auxiliary counter
that incremented while waiting for the handshake to complete, and I
couldn't figure out why it kept failing induction. Took me a while
(and some reading) to realise that in an arbitrary start state the
counter could be anything, so of course the property wasn't inductive.
Replaced it with an FSM-state invariant:

```
assert (fv_w_state == W_RESP |-> bvalid)
```

which is directly k-inductive once you also assert `fv_w_state` is
always one of its three legal encodings. Same idea fixed the read-side
bounded wait, though that one needed two consecutive cycles in R_DATA
because the slave's read FSM registers `rdata` for one extra cycle
before raising `rvalid` -- I missed that on the first pass and the
assertion failed at base case step 3 until I added the `$past` guard.

Data integrity was worse. I spent a while trying to close `a14_inv`
under k-induction but kept running into the fact that `mem[]` is
unconstrained in the arbitrary start state -- the prover could start
with the scoreboard tracking one value and the memory holding
something completely different. I tried:

- Exposing `mem[f_watch_idx]` as a new output `fv_mem_at_watch` on the
  slave and adding a memory-shadow invariant
  `fv_mem_at_watch == f_watch_data`.
- Tightening the scoreboard write to match the slave's *exact* write
  condition (`fv_w_state == W_DATA && wvalid && wready`) so an arbitrary
  state where `wready` happens to be high outside W_DATA doesn't
  desync them.

That got me a lot closer but I couldn't fully close `a14_inv` in the
time I wanted to spend. Rather than leave a broken claim in the README
I dropped the `prf` task and kept BMC to depth 20. The assertions hold
for every 20-cycle prefix, which is still a real result -- it's just
not the "proof over all time" that k-induction gives you. This is
something I'd come back to.

One smaller thing that confused me for a bit: sby's `[script]` section
doesn't support the same task-name prefix (`prf: ...`) that `[options]`
does. I tried `prf: read -formal ...` expecting it to only run for the
prf task and got `ERROR: No such command: prf` from yosys. Took me a
minute to realise the prefix filter only works in some sections, not
all.

## What I'd do next

- Actually close k-induction on the data-integrity lemma. Probably
  needs a stronger whole-memory invariant, or abstracting `mem[]` with
  an `anyseq` at reset.
- Cover back-to-back transactions and interleaved read/write.
- Try the same flow on a bigger AXI4 slave with bursts.
- Add HDL backdoor paths (`add_hdl_path` / `add_hdl_path_slice`) so
  the library `uvm_reg_access_seq` works on this DUT.
- Add functional coverage to the UVM env -- cover groups on
  register addresses, RW kinds, response codes, back-to-back
  transactions.
- Run on Questa or VCS via CSU's lab Linux box for a real-tool
  regression run instead of the Riviera EDU edition.

## See also

- `docs/bugs_found.md` -- step-by-step walkthrough of the injected bug
