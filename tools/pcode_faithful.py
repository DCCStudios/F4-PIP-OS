#!/usr/bin/env python3
# PIP-OS shell P-code faithfulness check (Round-9).
# The "47/48 byte-identical" check EXEMPTED PipboyMenu itself, hiding that ffdec -replace
# recompiles the whole class from .as and can drift the bytecode of even unmodified vanilla
# methods (dropped coercions, initproperty->setproperty, etc.). This diffs the P-code of every
# vanilla-source method in PipboyMenu between the vanilla SWF export and the built SWF export.
#
# Usage: python pcode_faithful.py <vanilla_PipboyMenu.pcode> <built_PipboyMenu.pcode> [--added name ...]
# Exit 0 = every shared (vanilla-source) method is normalized-identical; nonzero = drift found.
import re, sys, difflib

def parse(path):
    txt = open(path, encoding='utf-8', errors='replace').read().splitlines()
    methods = {}; pending = None; incode = False; code = []
    for ln in txt:
        s = ln.strip()
        m = re.match(r'trait (method|getter|setter) QName\(.*,"([^"]+)"\)\s*$', s)
        if m:
            k = m.group(1); suf = '#get' if k=='getter' else '#set' if k=='setter' else ''
            pending = m.group(2)+suf; continue
        if s == 'code': incode = True; code = []; continue
        if s.startswith('end ; code'):
            incode = False
            if pending is not None: methods[pending] = code; pending = None
            continue
        if incode: code.append(s)
    return methods

def norm(op):
    # Collapse only the representation noise a faithful build may legitimately vary:
    #  - private-namespace *naming* (null,"14" vs "PipboyMenu") - same private scope
    #  - branch offset labels, and the huge open-namespace multiname sets on unqualified names
    op = re.sub(r'PrivateNamespace\((?:null,"\d+"|"[^"]*")\)', 'PrivNS', op)
    op = re.sub(r'ProtectedNamespace\("[^"]*"\)', 'ProtNS', op)
    op = re.sub(r'StaticProtectedNs\("[^"]*"\)', 'SProtNS', op)
    op = re.sub(r'PackageInternalNs\("[^"]*"\)', 'PkgIntNS', op)
    op = re.sub(r'ofs[0-9a-fA-F]+', 'OFS', op)
    op = re.sub(r'^OFS:', 'LBL:', op)
    op = re.sub(r'MultinameL\(\[.*\]\)', 'MultinameL[..]', op)
    op = re.sub(r'Multiname\("([^"]+)",\[.*\]\)', r'Multiname("\1")', op)
    op = re.sub(r'QName\(PackageNamespace\(""\),"(length|content|contentLoaderInfo|fixed|addEventListener|load|SetPlatform|CalculatePageTextBounds)"\)', r'Multiname("\1")', op)
    op = re.sub(r'debug .*', 'debug', op)   # ffdec debug opcodes are register-name hints only
    return op

added = set()
if '--added' in sys.argv:
    i = sys.argv.index('--added'); added = set(sys.argv[i+1:]); sys.argv = sys.argv[:i]

va = parse(sys.argv[1]); pa = parse(sys.argv[2])
only_p = sorted(set(pa) - set(va) - added)
missing = sorted(set(va) - set(pa))
drift = []
for name in sorted(set(va) & set(pa)):
    v = [norm(x) for x in va[name]]; p = [norm(x) for x in pa[name]]
    if v != p:
        drift.append(name)

print(f"vanilla methods: {len(va)}   built methods: {len(pa)}")
if missing:  print("MISSING vanilla methods in build:", missing)
if only_p:   print("UNDECLARED extra methods (not in --added allowlist):", only_p)
if drift:
    print(f"BYTECODE DRIFT in {len(drift)} vanilla-source method(s): {drift}")
    for name in drift:
        v=[norm(x) for x in va[name]]; p=[norm(x) for x in pa[name]]
        print(f"\n--- {name} ---")
        for line in difflib.unified_diff(v,p,lineterm='',n=0):
            if not line.startswith(('---','+++','@@')): print("   "+line)
ok = (not missing and not only_p and not drift)
print("\nRESULT:", "PASS (shell bytecode faithful)" if ok else "FAIL (see drift above)")
sys.exit(0 if ok else 1)
