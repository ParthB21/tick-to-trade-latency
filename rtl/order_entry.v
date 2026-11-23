// order_entry.v  (Parth, M2)
// Builds market messages from keyboard keys, in the SAME 32-bit format as the ROM,
// and hands them to the order arbiter (valid/ready, held until accepted).
//
// Key grammar (Enter submits, Esc clears, Backspace deletes the last digit):
//   B <price> Space <qty> Enter   ADD bid         S (or A) ... : ADD ask
//   X (or C) <id> Enter           CANCEL one of our keyboard orders
//   T <id> Space <qty> Enter      TRADE against one of our keyboard orders
// Numbers are up to 4 digits, stored as typed (BCD) and converted to binary with
// shifts and adds (x10 = x<<3 + x<<1 ...), so there is no divider.
// ADD gets the next keyboard order ID (1, 2, ... 1023, then 1 again). The arbiter
// adds the source bit, so keyboard IDs never clash with ROM IDs.
//
// Rejected with "Err" (nothing is sent): price > 63, qty 0 or > 8191,
// id 0 or > 1023, or an ADD that would cross the book (bid >= best ask, ask <= best bid).
//
// FSM
//   CMD  : waiting for a command letter (B S X T)
//   NUM1 : typing the first number (price for B/S, id for X/T)
//   NUM2 : typing the second number (qty for B/S/T)       (Space moves NUM1 -> NUM2)
//   SEND : k_valid = 1 until the arbiter accepts (k_ready); keys are ignored here
// A command letter in CMD/NUM1/NUM2 starts a new command; Esc goes back to CMD.
//
// Display (6 HEX digits, codes for seg7.v), so the user sees what they typed:
//   nothing yet      : - - - - - -
//   typing           : [b|S|C|t] [P|q|d] then up to 4 digits (P price, q qty, d id)
//   sent             : [b|S|C|t] d 0007        (the order ID; leading zeros)
//   rejected         : E r r
module order_entry (
    input             clk,
    input             resetn,

    input             key_valid,
    input      [4:0]  key_code,

    // top of book, for the crossing check
    input      [5:0]  best_bid,
    input             bid_valid,
    input      [5:0]  best_ask,
    input             ask_valid,

    // to the arbiter
    output            k_valid,
    output reg [31:0] k_msg,
    input             k_ready,

    // status
    output reg [9:0]  next_id,          // ID the next ADD will get
    output reg [15:0] sent_count,
    output reg [15:0] err_count,
    output     [29:0] disp,             // 6 x 5-bit seg7 codes, HEX5 in [29:25]
    output     [1:0]  state_out
);
    localparam S_CMD = 2'd0, S_NUM1 = 2'd1, S_NUM2 = 2'd2, S_SEND = 2'd3;
    localparam M_BUY = 2'd0, M_SELL = 2'd1, M_CANCEL = 2'd2, M_TRADE = 2'd3;
    localparam K_BUY = 5'd10, K_SELL = 5'd11, K_CANCEL = 5'd12, K_TRADE = 5'd13,
               K_SPACE = 5'd14, K_ENTER = 5'd15, K_ESC = 5'd16, K_BKSP = 5'd17;
    localparam ST_IDLE = 2'd0, ST_OK = 2'd1, ST_ERR = 2'd2;
    localparam T_ADD = 2'b00, T_CANCEL = 2'b01, T_TRADE = 2'b10;
    localparam C_DASH = 5'd10, C_BLANK = 5'd15, C_b = 5'd16, C_S = 5'd17, C_C = 5'd18, C_t = 5'd19,
               C_E = 5'd20, C_r = 5'd21, C_d = 5'd22, C_P = 5'd23, C_q = 5'd24;

    reg [1:0]  state, mode, status;
    reg [15:0] dig;                     // 4 BCD digits, dig[3:0] = last typed
    reg [2:0]  ndig;                    // digits typed (0..4)
    reg [13:0] num1;                    // first number, in binary
    reg [9:0]  last_id;

    assign k_valid   = (state == S_SEND);
    assign state_out = state;

    // ---------------- BCD -> binary (shifts and adds only) ----------------
    function [13:0] times10(input [13:0] x);   times10 = (x << 3) + (x << 1);                 endfunction
    function [13:0] times100(input [13:0] x);  times100 = (x << 6) + (x << 5) + (x << 2);     endfunction
    function [13:0] times1000(input [13:0] x); times1000 = (x << 10) - (x << 4) - (x << 3);   endfunction
    wire [13:0] value = times1000({10'd0, dig[15:12]}) + times100({10'd0, dig[11:8]})
                      + times10({10'd0, dig[7:4]}) + {10'd0, dig[3:0]};

    // ---------------- checks at Enter ----------------
    wire is_add   = (mode == M_BUY) || (mode == M_SELL);
    wire price_ok = (num1 <= 14'd63);
    wire qty_ok   = (value != 14'd0) && (value <= 14'd8191);
    wire id1_ok   = (num1 != 14'd0) && (num1 <= 14'd1023);   // TRADE: id in num1
    wire idv_ok   = (value != 14'd0) && (value <= 14'd1023); // CANCEL: id in value
    wire crosses  = (mode == M_BUY)  ? (ask_valid && num1[5:0] >= best_ask)
                                     : (bid_valid && num1[5:0] <= best_bid);
    wire add_ok   = price_ok && qty_ok && !crosses;
    wire trade_ok = id1_ok && qty_ok;

    wire enter_cancel = (mode == M_CANCEL) && (state == S_NUM1);
    wire enter_two    = (mode != M_CANCEL) && (state == S_NUM2);
    wire submit_ok    = enter_cancel ? idv_ok : is_add ? add_ok : trade_ok;

    wire [31:0] new_msg =
        is_add            ? {T_ADD, (mode == M_SELL), num1[5:0], next_id, value[12:0]} :
        (mode == M_CANCEL)? {T_CANCEL, 1'b0, 6'd0, value[9:0], 13'd0} :
                            {T_TRADE, 1'b0, 6'd0, num1[9:0], value[12:0]};

    // ---------------- FSM ----------------
    always @(posedge clk) begin
        if (!resetn) begin
            state <= S_CMD; mode <= M_BUY; status <= ST_IDLE;
            dig <= 16'd0; ndig <= 3'd0; num1 <= 14'd0;
            k_msg <= 32'd0; next_id <= 10'd1; last_id <= 10'd0;
            sent_count <= 16'd0; err_count <= 16'd0;
        end else if (state == S_SEND) begin
            if (k_ready) begin                                   // accepted by the arbiter
                state <= S_CMD; status <= ST_OK; sent_count <= sent_count + 1'b1;
                last_id <= k_msg[22:13];
                if (is_add) next_id <= (next_id == 10'd1023) ? 10'd1 : next_id + 1'b1;
            end
        end else if (key_valid) begin
            case (key_code)
                K_ESC: begin state <= S_CMD; status <= ST_IDLE; end
                K_BUY, K_SELL, K_CANCEL, K_TRADE: begin
                    mode  <= (key_code == K_BUY)    ? M_BUY    :
                             (key_code == K_SELL)   ? M_SELL   :
                             (key_code == K_CANCEL) ? M_CANCEL : M_TRADE;
                    state <= S_NUM1; status <= ST_IDLE;
                    dig <= 16'd0; ndig <= 3'd0;
                end
                K_BKSP: if (state != S_CMD && ndig != 3'd0) begin
                    dig <= {4'd0, dig[15:4]}; ndig <= ndig - 1'b1;
                end
                K_SPACE: if (state == S_NUM1 && mode != M_CANCEL && ndig != 3'd0) begin
                    num1 <= value; state <= S_NUM2; dig <= 16'd0; ndig <= 3'd0;
                end
                K_ENTER: if ((enter_cancel || enter_two) && ndig != 3'd0) begin
                    if (submit_ok) begin
                        k_msg <= new_msg; state <= S_SEND;
                    end else begin
                        state <= S_CMD; status <= ST_ERR; err_count <= err_count + 1'b1;
                    end
                end
                default: if (key_code < 5'd10 && state != S_CMD && ndig != 3'd4) begin   // a digit
                    dig <= {dig[11:0], key_code[3:0]}; ndig <= ndig + 1'b1;
                end
            endcase
        end
    end

    // ---------------- display ----------------
    wire [19:0] id_bcd;
    bin2bcd_comb u_id (.bin({4'd0, last_id}), .bcd(id_bcd));

    wire [4:0] letter = (mode == M_BUY) ? C_b : (mode == M_SELL) ? C_S : (mode == M_CANCEL) ? C_C : C_t;
    wire [4:0] field  = (state == S_NUM2) ? C_q : (is_add ? C_P : C_d);

    // typed digits, right-aligned, blank where nothing was typed
    wire [4:0] t3 = (ndig >= 3'd4) ? {1'b0, dig[15:12]} : C_BLANK;
    wire [4:0] t2 = (ndig >= 3'd3) ? {1'b0, dig[11:8]}  : C_BLANK;
    wire [4:0] t1 = (ndig >= 3'd2) ? {1'b0, dig[7:4]}   : C_BLANK;
    wire [4:0] t0 = (ndig >= 3'd1) ? {1'b0, dig[3:0]}   : C_BLANK;

    assign disp =
        (state != S_CMD)   ? {letter, field, t3, t2, t1, t0} :
        (status == ST_OK)  ? {letter, C_d, 1'b0, id_bcd[15:12], 1'b0, id_bcd[11:8],
                                           1'b0, id_bcd[7:4],   1'b0, id_bcd[3:0]} :
        (status == ST_ERR) ? {C_E, C_r, C_r, C_BLANK, C_BLANK, C_BLANK} :
                             {6{C_DASH}};
endmodule
