// order_book.v  (Parth)
// Keeps the live limit order book for one stock with 64 price levels per side.
//
// Storage:
//   order table  otab[1024]  : per order ID -> {valid, side, price, qty}   (RAM)
//   level qty    lvl[128]    : total qty at {side, price}                  (RAM)
//   level view   lvl_view[128]: identical copy of lvl, read by the dashboard /
//                               board display through the query port      (RAM)
//   bid_mask, ask_mask       : bit p = 1 if that price level has any qty   (registers)
//   best bid / best ask      : priority encoders on the masks              (combinational)
//
// Message handling:
//   ADD    : write the order into the table, add qty to its level
//   CANCEL : look the order up, subtract its remaining qty from its level, delete it
//   TRADE  : look the order up, subtract the traded qty (partial or full);
//            also emits trade_valid/side/price/qty for the matching engine (M2)
//   unknown order IDs are ignored
//
// RAMs cannot be reset, so after reset the FSM walks every address and writes
// zeros (CLEAR state, ~1024 cycles = 20 us) before accepting messages.
//
// Timing: one message takes 4 cycles (ADD) or 5 cycles (CANCEL/TRADE) from
// acceptance to the done pulse. best_bid/best_ask are already updated when done = 1.
module order_book (
    input             clk,
    input             resetn,

    // Message in (valid/ready handshake)
    input             in_valid,
    output            in_ready,
    input      [1:0]  in_type,
    input             in_side,
    input      [5:0]  in_price,
    input      [9:0]  in_id,
    input      [12:0] in_qty,
    output            done,           // 1-cycle pulse when the message has been applied

    // Top of book
    output     [5:0]  best_bid,
    output            bid_valid,
    output     [5:0]  best_ask,
    output            ask_valid,
    output reg [63:0] bid_mask,
    output reg [63:0] ask_mask,

    // Trade event for the matching engine (M2), 1-cycle pulse together with done
    output            trade_valid,
    output reg        trade_side,
    output reg [5:0]  trade_price,
    output reg [12:0] trade_qty,

    // Query port: read the qty at any level. Result is valid 1 cycle after the address.
    input             q_side,
    input      [5:0]  q_level,
    output reg [12:0] q_qty,

    output     [2:0]  state_out
);
    localparam ADD = 2'b00, CANCEL = 2'b01, TRADE = 2'b10;

    localparam S_CLEAR   = 3'd0,
               S_IDLE    = 3'd1,
               S_ADD_TBL = 3'd2,
               S_TBL_RD  = 3'd3,
               S_TBL_CHK = 3'd4,
               S_LVL_RD  = 3'd5,
               S_LVL_UPD = 3'd6,
               S_DONE    = 3'd7;

    reg [2:0] state;
    assign state_out = state;
    assign in_ready  = (state == S_IDLE);
    assign done      = (state == S_DONE);

    // ---------------- latched message ----------------
    reg [1:0]  m_type;
    reg        m_side;
    reg [5:0]  m_price;
    reg [9:0]  m_id;
    reg [12:0] m_qty;

    // ---------------- level update request ----------------
    reg        l_side;      // which side's level to update
    reg [5:0]  l_price;     // which level
    reg        l_inc;       // 1 = add l_amt, 0 = subtract l_amt
    reg [12:0] l_amt;
    reg        is_trade;    // emit a trade event at DONE

    // ---------------- clear counter ----------------
    reg [9:0]  clr_addr;

    // =====================================================================
    // Order table RAM: 1024 x 21  {valid[20], side[19], price[18:13], qty[12:0]}
    // =====================================================================
    (* ramstyle = "no_rw_check" *) reg [20:0] otab [0:1023];
    reg [20:0] otab_q;
    reg        otab_we;
    reg [9:0]  otab_waddr;
    reg [20:0] otab_wdata;

    always @(posedge clk) begin
        if (otab_we) otab[otab_waddr] <= otab_wdata;
        otab_q <= otab[m_id];
    end

    wire        e_valid = otab_q[20];
    wire        e_side  = otab_q[19];
    wire [5:0]  e_price = otab_q[18:13];
    wire [12:0] e_qty   = otab_q[12:0];

    // =====================================================================
    // Level quantity RAM (128 x 13, address = {side, price}) + identical view copy
    // =====================================================================
    (* ramstyle = "no_rw_check" *) reg [12:0] lvl      [0:127];
    reg [12:0] lvl_view [0:127];
    reg [12:0] lvl_q;
    reg        lvl_we;
    reg [6:0]  lvl_waddr;
    reg [12:0] lvl_wdata;

    always @(posedge clk) begin
        if (lvl_we) lvl[lvl_waddr] <= lvl_wdata;
        lvl_q <= lvl[{l_side, l_price}];
    end

    always @(posedge clk) begin
        if (lvl_we) lvl_view[lvl_waddr] <= lvl_wdata;
        q_qty <= lvl_view[{q_side, q_level}];
    end

    // new level quantity (saturating add, floor-at-zero subtract)
    wire [13:0] lvl_sum = {1'b0, lvl_q} + {1'b0, l_amt};
    wire [12:0] lvl_new = l_inc ? (lvl_sum[13] ? 13'h1FFF : lvl_sum[12:0])
                                : ((lvl_q > l_amt) ? (lvl_q - l_amt) : 13'd0);

    // amount a CANCEL / TRADE removes from the order
    wire [12:0] dec_amt = (m_type == CANCEL) ? e_qty
                        : ((m_qty < e_qty) ? m_qty : e_qty);
    wire [12:0] remain  = e_qty - dec_amt;

    // RAM write controls (combinational from state)
    always @* begin
        otab_we = 1'b0; otab_waddr = m_id; otab_wdata = 21'd0;
        lvl_we  = 1'b0; lvl_waddr  = {l_side, l_price}; lvl_wdata = lvl_new;
        case (state)
            S_CLEAR: begin
                otab_we = 1'b1; otab_waddr = clr_addr; otab_wdata = 21'd0;
                lvl_we  = 1'b1; lvl_waddr  = clr_addr[6:0]; lvl_wdata = 13'd0;
            end
            S_ADD_TBL: begin
                otab_we = 1'b1; otab_wdata = {1'b1, m_side, m_price, m_qty};
            end
            S_TBL_CHK: if (e_valid) begin
                otab_we    = 1'b1;
                otab_wdata = (remain == 13'd0) ? 21'd0 : {1'b1, e_side, e_price, remain};
            end
            S_LVL_UPD: lvl_we = 1'b1;
            default: ;
        endcase
    end

    // ---------------- control FSM ----------------
    always @(posedge clk) begin
        if (!resetn) begin
            state    <= S_CLEAR;
            clr_addr <= 10'd0;
            bid_mask <= 64'd0;
            ask_mask <= 64'd0;
            is_trade <= 1'b0;
            m_type <= 2'd0; m_side <= 1'b0; m_price <= 6'd0; m_id <= 10'd0; m_qty <= 13'd0;
            l_side <= 1'b0; l_price <= 6'd0; l_inc <= 1'b0; l_amt <= 13'd0;
            trade_side <= 1'b0; trade_price <= 6'd0; trade_qty <= 13'd0;
        end else begin
            case (state)
                S_CLEAR: begin
                    clr_addr <= clr_addr + 1'b1;
                    if (clr_addr == 10'd1023) state <= S_IDLE;
                end

                S_IDLE: if (in_valid) begin
                    m_type <= in_type; m_side <= in_side; m_price <= in_price;
                    m_id   <= in_id;   m_qty  <= in_qty;
                    is_trade <= 1'b0;
                    case (in_type)
                        ADD:          state <= S_ADD_TBL;
                        CANCEL,TRADE: state <= S_TBL_RD;
                        default:      state <= S_DONE;     // unknown type: ignore
                    endcase
                end

                S_ADD_TBL: begin                           // table written this cycle (see above)
                    l_side <= m_side; l_price <= m_price;
                    l_inc  <= 1'b1;   l_amt   <= m_qty;
                    state  <= S_LVL_RD;
                end

                S_TBL_RD: state <= S_TBL_CHK;              // otab[m_id] is read this cycle

                S_TBL_CHK: begin
                    if (!e_valid)
                        state <= S_DONE;                   // unknown order ID: ignore
                    else begin
                        l_side <= e_side; l_price <= e_price;
                        l_inc  <= 1'b0;   l_amt   <= dec_amt;
                        if (m_type == TRADE) begin
                            is_trade    <= 1'b1;
                            trade_side  <= e_side;
                            trade_price <= e_price;
                            trade_qty   <= dec_amt;
                        end
                        state <= S_LVL_RD;
                    end
                end

                S_LVL_RD: state <= S_LVL_UPD;              // lvl[{l_side,l_price}] is read this cycle

                S_LVL_UPD: begin                           // lvl written this cycle; update the mask
                    if (l_side == 1'b0) bid_mask[l_price] <= (lvl_new != 13'd0);
                    else                ask_mask[l_price] <= (lvl_new != 13'd0);
                    state <= S_DONE;
                end

                S_DONE: state <= S_IDLE;

                default: state <= S_IDLE;
            endcase
        end
    end

    assign trade_valid = done & is_trade;

    // ---------------- best bid / best ask ----------------
    prio_enc64 #(.HIGHEST(1)) u_bid (.in(bid_mask), .idx(best_bid), .valid(bid_valid));
    prio_enc64 #(.HIGHEST(0)) u_ask (.in(ask_mask), .idx(best_ask), .valid(ask_valid));
endmodule
