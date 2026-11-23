"""
Reference model of the keyboard side (Parth, M2):
  kb_decoder.v  : PS/2 scan codes -> key events (make codes only)
  order_entry.v : key events -> one 32-bit market message (same format as the ROM)

Key grammar (Enter submits, Esc clears, Backspace deletes the last digit):
  B <price> Space <qty> Enter    ADD bid      (A is the same as S, C the same as X)
  S <price> Space <qty> Enter    ADD ask
  X <id> Enter                   CANCEL one of our keyboard orders
  T <id> Space <qty> Enter       TRADE against one of our keyboard orders
Numbers are up to 4 decimal digits. ADD orders get the next keyboard order ID
(1, 2, 3, ... wrapping 1023 -> 1). Keyboard IDs are a separate ID space from the
ROM's: the arbiter adds a source bit, so keyboard ID 5 never touches ROM order 5.

Rejected (shows "Err", nothing is sent):
  price > 63, qty = 0 or > 8191, id = 0 or > 1023,
  an ADD that would cross the book (bid >= best ask, or ask <= best bid).
"""
from msgfmt import ADD, CANCEL, TRADE, BID, ASK, pack

# key codes used inside the hardware (kb_decoder.v -> order_entry.v)
K_BUY, K_SELL, K_CANCEL, K_TRADE, K_SPACE, K_ENTER, K_ESC, K_BKSP = range(10, 18)
K_UP, K_DOWN, K_LEFT, K_RIGHT = range(18, 22)          # arrows: VGA book cursor, order entry ignores them
EXT_CODES = {0x5A: K_ENTER, 0x75: K_UP, 0x72: K_DOWN, 0x6B: K_LEFT, 0x74: K_RIGHT}

# PS/2 set-2 make codes
DIGIT_CODES = [0x45, 0x16, 0x1E, 0x26, 0x25, 0x2E, 0x36, 0x3D, 0x3E, 0x46]   # top row 0..9
KEYPAD_CODES = [0x70, 0x69, 0x72, 0x7A, 0x6B, 0x73, 0x74, 0x6C, 0x75, 0x7D]  # keypad 0..9
LETTER_CODES = {
    0x32: K_BUY,     # B
    0x1B: K_SELL,    # S
    0x1C: K_SELL,    # A (ask)
    0x22: K_CANCEL,  # X
    0x21: K_CANCEL,  # C
    0x2C: K_TRADE,   # T
    0x29: K_SPACE,
    0x5A: K_ENTER,   # also keypad Enter (E0 5A)
    0x76: K_ESC,
    0x66: K_BKSP,
}

# characters used in test scripts -> make code
CHAR_CODES = {str(d): DIGIT_CODES[d] for d in range(10)}
CHAR_CODES.update({"B": 0x32, "S": 0x1B, "A": 0x1C, "X": 0x22, "C": 0x21, "T": 0x2C,
                   " ": 0x29, "\n": 0x5A, "!": 0x76, "<": 0x66})


def scan_code_to_key(code, extended=False):
    """Same table as kb_decoder.v. Returns a key code or None (key ignored)."""
    if extended:
        return EXT_CODES.get(code)
    if code in DIGIT_CODES:
        return DIGIT_CODES.index(code)
    if code in KEYPAD_CODES:
        return KEYPAD_CODES.index(code)
    return LETTER_CODES.get(code)


# extended keys in test strings: '~' keypad Enter (E0 5A), '^' up arrow (E0 75, ignored by order entry)
EXT_CHARS = {"~": 0x5A, "^": 0x75}


def text_to_scan_bytes(text):
    """A typed string -> the bytes a keyboard sends (make, then F0 + make on release;
    extended keys: E0 make, then E0 F0 make)."""
    out = []
    for ch in text:
        if ch in EXT_CHARS:
            code = EXT_CHARS[ch]
            out += [0xE0, code, 0xE0, 0xF0, code]
        else:
            code = CHAR_CODES[ch]
            out += [code, 0xF0, code]
    return out


def char_to_key(ch):
    if ch in EXT_CHARS:
        return scan_code_to_key(EXT_CHARS[ch], extended=True)
    return scan_code_to_key(CHAR_CODES[ch])


M_NONE, M_BUY, M_SELL, M_CANCEL, M_TRADE = range(5)
MAX_PRICE, MAX_QTY, MAX_ID = 63, 8191, 1023


class OrderEntry:
    def __init__(self):
        self.mode = M_NONE
        self.field = 1
        self.digits = []
        self.num1 = 0
        self.next_id = 1
        self.status = "idle"         # "idle", "ok", "err"
        self.last_id = 0
        self.sent = 0
        self.errors = 0

    def _value(self):
        v = 0
        for d in self.digits:
            v = v * 10 + d
        return v

    def key(self, k, top):
        """One key event. top = (best_bid, bid_valid, best_ask, ask_valid).
        Returns a 32-bit message word, or None."""
        if k == K_ESC:
            self.mode, self.digits, self.status = M_NONE, [], "idle"
            return None
        if k in (K_BUY, K_SELL, K_CANCEL, K_TRADE):
            self.mode = {K_BUY: M_BUY, K_SELL: M_SELL, K_CANCEL: M_CANCEL, K_TRADE: M_TRADE}[k]
            self.field, self.digits, self.status = 1, [], "idle"
            return None
        if self.mode == M_NONE:
            return None
        if k < 10:
            if len(self.digits) < 4:
                self.digits.append(k)
            return None
        if k == K_BKSP:
            if self.digits:
                self.digits.pop()
            return None
        if k == K_SPACE:
            if self.mode != M_CANCEL and self.field == 1 and self.digits:
                self.num1, self.field, self.digits = self._value(), 2, []
            return None
        if k == K_ENTER:
            if not self.digits:
                return None
            if self.mode == M_CANCEL and self.field == 1:
                return self._submit(self._value(), 0, top)
            if self.mode != M_CANCEL and self.field == 2:
                return self._submit(self.num1, self._value(), top)
        return None

    def _submit(self, n1, n2, top):
        best_bid, bid_valid, best_ask, ask_valid = top
        mode = self.mode
        self.mode, self.digits = M_NONE, []
        word = None
        if mode in (M_BUY, M_SELL):
            price, qty = n1, n2
            cross = (mode == M_BUY and ask_valid and price >= best_ask) or \
                    (mode == M_SELL and bid_valid and price <= best_bid)
            if price <= MAX_PRICE and 1 <= qty <= MAX_QTY and not cross:
                oid = self.next_id
                word = pack(ADD, BID if mode == M_BUY else ASK, price, oid, qty)
                self.next_id = 1 if oid == MAX_ID else oid + 1
        elif mode == M_CANCEL:
            oid = n1
            if 1 <= oid <= MAX_ID:
                word = pack(CANCEL, 0, 0, oid, 0)
        else:
            oid, qty = n1, n2
            if 1 <= oid <= MAX_ID and 1 <= qty <= MAX_QTY:
                word = pack(TRADE, 0, 0, oid, qty)
        if word is None:
            self.status = "err"
            self.errors += 1
        else:
            self.status, self.last_id = "ok", oid
            self.sent += 1
        return word


def type_text(entry, text, top):
    """Type a whole string; returns the list of messages it produced."""
    out = []
    for ch in text:
        k = char_to_key(ch)
        w = entry.key(k, top) if k is not None else None
        if w is not None:
            out.append(w)
    return out
