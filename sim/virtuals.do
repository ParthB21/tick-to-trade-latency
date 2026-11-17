virtual type { CLEAR IDLE ADD_TBL TBL_RD TBL_CHK LVL_RD LVL_UPD DONE} book_state_t
virtual function -install /order_book_tb/dut -env /order_book_tb/#INITIAL#98 { (book_state_t)/order_book_tb/dut/state} book_state
