virtual type { CLEAR IDLE ADD_TBL TBL_RD TBL_CHK LVL_RD LVL_UPD DONE} book_state_t
virtual function -install /order_book_tb/dut -env /order_book_tb/#INITIAL#98 { (book_state_t)/order_book_tb/dut/state} book_state
virtual type { IDLE READ LATCH SEND WAIT FINISHED} feed_state_t
virtual function -install /feed_book_tb -env /feed_book_tb/#INITIAL#70 { (feed_state_t)/feed_book_tb/feed_state} feed_state_name
virtual function -install /feed_book_tb -env /feed_book_tb/#INITIAL#70 { (book_state_t)/feed_book_tb/book_state} book_state_name
