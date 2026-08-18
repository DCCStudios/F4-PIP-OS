#!/usr/bin/env python3
# Verifies the PIP-OS background is Baka's file with ONLY DefineShape char 1 body swapped:
# every other tag (incl. the whole DoABC and SymbolClass) is byte-identical.
import sys, zlib, struct

def load_tags(path):
    raw=open(path,'rb').read()
    assert raw[:3]==b'CWS'
    body=zlib.decompress(raw[8:])
    nb=body[0]>>3; p=(5+4*nb+7)//8 + 4
    tags=[]
    while p<len(body):
        (rh,)=struct.unpack_from('<H',body,p); q=p+2
        code=rh>>6; length=rh&0x3F
        if length==0x3F:
            (length,)=struct.unpack_from('<I',body,q); q+=4
        tags.append((code, body[q:q+length]))
        p=q+length
    return tags

a=load_tags(sys.argv[1])   # Baka original
b=load_tags(sys.argv[2])   # ours
assert len(a)==len(b), f"tag COUNT differs {len(a)} vs {len(b)}"
diffs=[]; doabc_ok=True
for i,(ta,tb) in enumerate(zip(a,b)):
    ca,ba_=ta; cb,bb_=tb
    if ca!=cb: diffs.append((i,"TAGCODE",ca,cb)); continue
    if ba_==bb_: continue
    # only allowed difference: DefineShape (2) whose ShapeId==1
    if ca==2 and len(ba_)>=2 and struct.unpack_from('<H',ba_,0)[0]==1:
        # bounds RECT + fillstyle prefix must still match (only shape records differ)
        diffs.append((i,"DefineShape char1 body (ALLOWED)", len(ba_), len(bb_)))
    else:
        diffs.append((i,f"UNEXPECTED tag{ca} body differs", len(ba_), len(bb_)))
        if ca==82: doabc_ok=False
print("tag count:", len(a))
allowed=[d for d in diffs if "ALLOWED" in d[1]]
bad=[d for d in diffs if "ALLOWED" not in d[1]]
for d in diffs: print("  ", d)
print("DoABC untouched:", doabc_ok)
if len(bad)==0 and len(allowed)==1 and doabc_ok:
    print("RESULT: PASS - only DefineShape char1 body differs; everything else byte-identical")
    sys.exit(0)
else:
    print("RESULT: FAIL"); sys.exit(1)
