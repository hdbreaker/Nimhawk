# Helper for packing BOF arguments
# Original source: COFFLoader by kev169 at TrustedSec
# https://github.com/trustedsec/COFFLoader/blob/main/beacon_generate.py
class BeaconPack:
    def __init__(self):
        self.buffer = b""
        self.size = 0

    def getbuffer(self):
        return pack("<L", self.size) + self.buffer

    def addshort(self, short):
        self.buffer += pack("<h", short)
        self.size += 2

    def addint(self, dint):
        self.buffer += pack("<i", dint)
        self.size += 4

    def addstr(self, s):
        if isinstance(s, str):
            s = s.encode("utf-8")
        fmt = "<L{}s".format(len(s) + 1)
        self.buffer += pack(fmt, len(s) + 1, s)
        self.size += calcsize(fmt)

    def addWstr(self, s):
        if isinstance(s, str):
            s = s.encode("utf-16_le")
        fmt = "<L{}s".format(len(s) + 2)
        self.buffer += pack(fmt, len(s) + 2, s)
        self.size += calcsize(fmt)

    def addbin(self, s):
        try:
            s = base64.b64decode(s)
        except:  # not b64, try raw encoding
            if isinstance(s, str):
                s = s.encode("utf-8")

        fmt = "<L{}s".format(len(s))
        self.buffer += pack(fmt, len(s), s)
        self.size += calcsize(fmt)
