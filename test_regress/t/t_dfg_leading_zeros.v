// DESCRIPTION: Verilator: Verilog Test module
//
// This file ONLY is placed under the Creative Commons Public Domain.
// SPDX-FileCopyrightText: 2026 Wilson Snyder
// SPDX-License-Identifier: CC0-1.0

// verilog_format: off
`define stop $stop
`define checkd(gotv,expv) do if ((gotv) !== (expv)) begin $write("%%Error: %s:%0d:  got=%0d exp=%0d\n", `__FILE__,`__LINE__, (gotv), (expv)); `stop; end while(0);
// verilog_format: on

// Like ChipForge's generated counters: a balanced tree of nonzero slice tests,
// with linear leaves of up to four bits and a common zero sentinel at every leaf.
module lzc_tree #(
    parameter int WIDTH = 26,
    parameter int LOW = 0,
    parameter int SPAN = WIDTH,
    parameter int OUT = $clog2(WIDTH + 1),
    parameter int MODE = 0,
    parameter int ZERO = WIDTH
) (
    input [WIDTH-1:0] value,
    output [OUT-1:0] count
);
  if (SPAN <= 4) begin : leaf
    wire [OUT-1:0] counts[SPAN:0];
    assign counts[0] = OUT'(ZERO);
    for (genvar i = 0; i < SPAN; ++i) begin : bit_test
      assign counts[i+1] = value[LOW+i] ? OUT'(WIDTH - 1 - LOW - i) : counts[i];
    end
    assign count = counts[SPAN];
  end
  else begin : branch
    localparam int HALF = SPAN / 2;
    wire [OUT-1:0] upper_count;
    wire [OUT-1:0] lower_count;
    lzc_tree #(WIDTH, LOW + HALF, SPAN - HALF, OUT, MODE, ZERO) upper (
        value,
        upper_count
    );
    lzc_tree #(WIDTH, LOW, HALF, OUT, MODE, ZERO) lower (
        value,
        lower_count
    );
    if (MODE == 0) begin
      assign count = value[LOW+HALF+:SPAN-HALF] != 0 ? upper_count : lower_count;
    end
    else if (MODE == 1) begin
      assign count = value[LOW+HALF+:SPAN-HALF] == 0 ? lower_count : upper_count;
    end
    else if (MODE == 2) begin
      assign count = (|value[LOW+HALF+:SPAN-HALF]) ? upper_count : lower_count;
    end
    else begin
      assign count = !(|value[LOW+HALF+:SPAN-HALF]) ? lower_count : upper_count;
    end
  end
endmodule

module lzc_check #(
    parameter int WIDTH = 26,
    parameter int MODE = 0,
    parameter int OUT = $clog2(WIDTH + 1),
    parameter int ZERO = WIDTH
) (
    input clk,
    input [95:0] stimulus
);
  wire [WIDTH-1:0] value = stimulus[WIDTH-1:0];
  wire [OUT-1:0] count;
  lzc_tree #(WIDTH, 0, WIDTH, OUT, MODE, ZERO) encoder (
      value,
      count
  );
  always @(posedge clk) begin
    // ceil(log2(x+1)) is the position of the highest set bit plus one, including
    // x=0. Keep the carry when x is all ones.
    `checkd(int'(count), int'($unsigned(
            OUT'(value == 0 ? ZERO : WIDTH - $clog2({1'b0, value} + (WIDTH + 1)'(1))))));
  end
endmodule

module t (
    input clk
);
  int cyc = 0;
  logic [95:0] stimulus = '0;
  logic [95:0] random_value = 96'hfedcba98_76543210_12345678;
  always @(negedge clk) begin
    cyc <= cyc + 1;
    random_value <= {
      random_value[94:0], random_value[95] ^ random_value[93] ^ random_value[48] ^ random_value[0]
    };
    if (cyc < 256) stimulus <= 96'(cyc);  // Exhaust the small encoders, including zero.
    else if (cyc < 352) stimulus <= 96'b1 << (cyc - 256);  // Every isolated bit.
    else if (cyc < 448) stimulus <= ~(96'b1 << (cyc - 352));
    else stimulus <= random_value >> (cyc % 96);  // Vary the leading-zero count.
    if (cyc == 2000) begin
      $write("*-* All Finished *-*\n");
      $finish;
    end
  end

  lzc_check #(7) c7 (
      clk,
      stimulus
  );
  lzc_check #(15, 1) c15 (
      clk,
      stimulus
  );
  lzc_check #(26) chipforge (
      clk,
      stimulus
  );
  lzc_check #(31, 2) c31 (
      clk,
      stimulus
  );
  lzc_check #(32, 3, 32) c32 (
      clk,
      stimulus
  );
  lzc_check #(33) c33 (
      clk,
      stimulus
  );
  lzc_check #(63, 1) c63 (
      clk,
      stimulus
  );
  lzc_check #(64, 2) c64 (
      clk,
      stimulus
  );
  lzc_check #(65, 3) c65 (
      clk,
      stimulus
  );
  lzc_check #(95) c95 (
      clk,
      stimulus
  );
  // A different zero sentinel must not be replaced by the ordinary LZC.
  lzc_check #(26, 0, 6, 29) sentinel (
      clk,
      stimulus
  );
  // Truncation can wrap the encoded positions and the zero sentinel.
  lzc_check #(33, 0, 5) truncated (
      clk,
      stimulus
  );

  // A shared intermediate result has the original whole-word zero sentinel.
  wire [4:0] upper_debug;
  lzc_tree #(26, 13, 13) upper_encoder (
      stimulus[25:0],
      upper_debug
  );
  always @(posedge clk) begin
    `checkd(int'(upper_debug), stimulus[25:13] == 0 ? 26 : 13 - $clog2(
            {1'b0, stimulus[25:13]} + 14'd1));
  end

  // Near misses: a different source bit, a skipped bit, and an incorrect value.
  wire [2:0] mixed = stimulus[6] ? 3'd0 : stimulus[5] ? 3'd1
      : stimulus[4] ? 3'd2 : stimulus[3] ? 3'd3 : stimulus[2] ? 3'd4
      : stimulus[1] ? 3'd5 : stimulus[7] ? 3'd6 : 3'd7;
  wire [2:0] skipped = stimulus[6] ? 3'd0 : stimulus[5] ? 3'd1
      : stimulus[4] ? 3'd2 : stimulus[3] ? 3'd3 : stimulus[2] ? 3'd4
      : stimulus[1] ? 3'd5 : 3'd7;
  wire [2:0] wrong_value = stimulus[6] ? 3'd0 : stimulus[5] ? 3'd1
      : stimulus[4] ? 3'd2 : stimulus[3] ? 3'd2 : stimulus[2] ? 3'd4
      : stimulus[1] ? 3'd5 : stimulus[0] ? 3'd6 : 3'd7;
  wire [2:0] upper_guess = stimulus[6] ? 3'd0 : stimulus[5] ? 3'd1
      : stimulus[4] ? 3'd2 : stimulus[3] ? 3'd3 : 3'd7;
  wire [2:0] lower_guess = stimulus[2] ? 3'd4 : stimulus[1] ? 3'd5 : stimulus[0] ? 3'd6 : 3'd7;
  // The guard does not cover all the bits encoded by its upper branch.
  wire [2:0] wrong_guard = (stimulus[6:4] != 0) ? upper_guess : lower_guess;
  always @(posedge clk) begin
    `checkd(int'(mixed), 7 - $clog2({1'b0, stimulus[6:1], stimulus[7]} + 8'd1));
    `checkd(int'(skipped), 7 - $clog2({1'b0, stimulus[6:1], 1'b0} + 8'd1));
    `checkd(int'(wrong_value), stimulus[6:3] == 4'b0001 ? 2 : 7 - $clog2(
            {1'b0, stimulus[6:0]} + 8'd1));
    `checkd(int'(wrong_guard), stimulus[6:4] != 0 ? 7 - $clog2({1'b0, stimulus[6:0]} + 8'd1
            ) : 7 - $clog2({5'b0, stimulus[2:0]} + 8'd1));
  end

  // Nonzero bounds and signed/ascending inputs must still refer to the same bits.
  wire signed [33:3] shifted = stimulus[30:0];
  wire [4:0] shifted_count = shifted[33] ? 5'd0 : shifted[32] ? 5'd1
      : shifted[31] ? 5'd2 : shifted[30] ? 5'd3 : shifted[29] ? 5'd4
      : shifted[28] ? 5'd5 : shifted[27] ? 5'd6 : 5'd7;
  // verilator lint_off ASCRANGE
  wire [0:6] ascending = stimulus[6:0];
  // verilator lint_on ASCRANGE
  wire [2:0] ascending_count = ascending[0] ? 3'd0 : ascending[1] ? 3'd1
      : ascending[2] ? 3'd2 : ascending[3] ? 3'd3 : ascending[4] ? 3'd4
      : ascending[5] ? 3'd5 : ascending[6] ? 3'd6 : 3'd7;
  always @(posedge clk) begin
    `checkd(int'(shifted_count), 7 - $clog2({1'b0, shifted[33:27]} + 8'd1));
    `checkd(int'(ascending_count), 7 - $clog2({1'b0, ascending} + 8'd1));
  end
endmodule
