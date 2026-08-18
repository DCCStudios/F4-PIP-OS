#!/usr/bin/env python3
# Round 16: shape-only tag surgery on Baka's PipboyBackgroundMenu.swf.
# Replaces ONLY the body of DefineShape character 1 (the background art rect) with a PIP-OS CRT bezel
# authored as filled rectangles (white fill; Baka's DLL tints via fPipboyEffectColor + alphas it).
# Everything else - SymbolClass, DoABC, sprite hierarchy, char IDs, PlaceObject, header/dims/fps - stays
# byte-identical. char 1 is a TOP-LEVEL tag so no sprite offsets are affected.
import sys, zlib, struct, io

# ---------- bit writer ----------
class BW:
    def __init__(self): self.bits=[]
    def u(self, val, n):
        for i in range(n-1,-1,-1): self.bits.append((val>>i)&1)
    def s(self, val, n):  # signed in n bits (twos complement)
        if val<0: val=(1<<n)+val
        self.u(val,n)
    def align(self):
        while len(self.bits)%8: self.bits.append(0)
    def bytes(self):
        self.align(); out=bytearray()
        for i in range(0,len(self.bits),8):
            b=0
            for j in range(8): b=(b<<1)|self.bits[i+j]
            out.append(b)
        return bytes(out)

def sbits_needed(vals):
    n=1
    for v in vals:
        v=int(v)
        # bits to hold signed v
        k=2
        while not (-(1<<(k-1)) <= v <= (1<<(k-1))-1): k+=1
        n=max(n,k)
    return n

def rect_bytes(xmin,xmax,ymin,ymax):
    vals=[xmin,xmax,ymin,ymax]
    nb=max(1,max(v.bit_length() for v in vals if v>=0) if any(v>0 for v in vals) else 1)
    # unsigned RECT coords use signed fields; use signed width
    nb=sbits_needed(vals)
    bw=BW(); bw.u(nb,5)
    for v in vals: bw.s(v,nb)
    return bw.bytes()

# ---------- DefineShape body builder (fill style 1 = solid white; filled rects) ----------
def build_shape_body(shape_id, rects, bounds):
    # rects: list of (x,y,w,h) in TWIPS. bounds: (xmin,xmax,ymin,ymax) twips.
    body=bytearray()
    body += struct.pack('<H', shape_id)               # ShapeId
    body += rect_bytes(*bounds)                        # ShapeBounds
    # FILLSTYLEARRAY: 1 solid white fill (RGB, DefineShape tag2 -> no alpha)
    body += bytes([0x01, 0x00, 0xFF, 0xFF, 0xFF])
    # LINESTYLEARRAY: 0
    body += bytes([0x00])
    # SHAPERECORDS
    NFILL=1; NLINE=0
    bw=BW(); bw.u(NFILL,4); bw.u(NLINE,4)
    cx=0; cy=0
    for (x,y,w,h) in rects:
        # StyleChangeRecord: MoveTo (x,y) + FillStyle1 = 1
        pts=[x,y]
        mbits=sbits_needed([x,y])
        bw.u(0,1)                 # TypeFlag=0 (non-edge)
        bw.u(0,1)                 # StateNewStyles=0
        bw.u(0,1)                 # StateLineStyle=0
        bw.u(1,1)                 # StateFillStyle1=1
        bw.u(0,1)                 # StateFillStyle0=0
        bw.u(1,1)                 # StateMoveTo=1
        bw.u(mbits,5); bw.s(x,mbits); bw.s(y,mbits)
        bw.u(1,NFILL)             # FillStyle1 index = 1
        cx,cy=x,y
        # 4 straight edges (rectangle): +w,0 ; 0,+h ; -w,0 ; 0,-h
        for (dx,dy) in [(w,0),(0,h),(-w,0),(0,-h)]:
            ebits=sbits_needed([dx,dy]);  ebits=max(2,ebits)
            bw.u(1,1)             # TypeFlag=1 edge
            bw.u(1,1)             # StraightFlag=1
            bw.u(ebits-2,4)       # NumBits (stored as NumBits-2)
            if dx!=0 and dy!=0:
                bw.u(1,1); bw.s(dx,ebits); bw.s(dy,ebits)   # general
            else:
                bw.u(0,1)         # GeneralLineFlag=0
                if dx!=0: bw.u(0,1); bw.s(dx,ebits)   # horizontal (VertFlag=0)
                else:     bw.u(1,1); bw.s(dy,ebits)   # vertical (VertFlag=1)
    # EndShapeRecord: TypeFlag=0 + 5 zero flags
    bw.u(0,6)
    body += bw.bytes()
    return bytes(body)

# ---------- PIP-OS bezel geometry (1920x1080 -> twips x20) ----------
def bezel_rects():
    T=20; W=1920*T; H=1080*T
    fr=14*T          # frame border thickness
    r=[]
    # outer frame ring (top/bottom/left/right bars) - leaves center aperture OPEN (world shows through)
    r.append((0,0,W,fr))            # top
    r.append((0,H-fr,W,fr))         # bottom
    r.append((0,0,fr,H))            # left
    r.append((W-fr,0,fr,H))         # right
    # inner hairline accent inset ~40px
    inset=40*T; hl=3*T
    r.append((inset,inset,W-2*inset,hl))
    r.append((inset,H-inset-hl,W-2*inset,hl))
    r.append((inset,inset,hl,H-2*inset))
    r.append((W-inset-hl,inset,hl,H-2*inset))
    # corner brackets (L shapes) just inside the frame
    bl=120*T; bt=6*T; off=fr+16*T
    for (cxq,cyq) in [(0,0),(1,0),(0,1),(1,1)]:
        bx=off if cxq==0 else W-off-bl
        by=off if cyq==0 else H-off-bl
        r.append((bx,by,bl,bt))                 # horizontal arm
        r.append((bx if cxq==0 else bx+bl-bt, by, bt, bl))  # vertical arm
    return r, (0,W,0,H)

# ---------- SWF tag walk + replace ----------
def read_tag_header(buf, p):
    (rh,)=struct.unpack_from('<H', buf, p); p+=2
    code=rh>>6; length=rh&0x3F
    longform=False
    if length==0x3F:
        (length,)=struct.unpack_from('<I', buf, p); p+=4; longform=True
    return code,length,p,longform

def write_tag(code, body):
    n=len(body)
    if n<0x3F:
        return struct.pack('<H',(code<<6)|n)+body
    else:
        return struct.pack('<H',(code<<6)|0x3F)+struct.pack('<I',n)+body

def main():
    src, dst = sys.argv[1], sys.argv[2]
    raw=open(src,'rb').read()
    sig=raw[:3]; ver=raw[3]; filelen=struct.unpack_from('<I',raw,4)[0]
    assert sig==b'CWS', "expected ZLIB (CWS) swf"
    body=zlib.decompress(raw[8:])
    # uncompressed full = 8-byte header + body ; parse body: frame RECT + rate + count + tags
    # find start of tags: skip frame RECT
    nb=body[0]>>3
    rect_bits=5+4*nb; rect_bytes_n=(rect_bits+7)//8
    p=rect_bytes_n+4   # + frameRate(2) + frameCount(2)
    tags_start=p
    out=bytearray(body[:tags_start])
    changed=[]
    while p < len(body):
        code,length,after,longform=read_tag_header(body,p)
        tagbody=body[after:after+length]
        if code==2 and length>=2 and struct.unpack_from('<H',tagbody,0)[0]==1:
            rects,bounds=bezel_rects()
            newbody=build_shape_body(1,rects,bounds)
            out+=write_tag(2,newbody)
            changed.append(('DefineShape char1', length, len(newbody)))
        else:
            out+=body[p:after+length]
        p=after+length
    newfilelen=8+len(out)
    comp=zlib.compress(bytes(out),9)
    with open(dst,'wb') as f:
        f.write(b'CWS'+bytes([ver])+struct.pack('<I',newfilelen)+comp)
    print("changed tags:", changed)
    print("wrote", dst, "filelen", newfilelen, "(was", filelen, ")")

if __name__=='__main__': main()
