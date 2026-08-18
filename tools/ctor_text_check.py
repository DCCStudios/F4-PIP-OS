#!/usr/bin/env python3
# Round-18 enforcement: NO TextField text/width mutation may be reachable from a page constructor.
# Vanilla idiom (Pipboy_RadioPage): fields timeline-instantiated, ctor sets ZERO .text/.width; all text
# deferred to post-attach callbacks. Our pages must build panels in the ctor (buildPanels) and defer ALL
# TextField creation/text to buildText() (called on stage attach via ensureText). This proves buildPanels
# is font-free.
import re, sys, glob, os
SRC=os.path.join(os.path.dirname(__file__),"..","InterfaceSource")
FORBIDDEN=["Theme.mk(","Theme.tf(","Theme.heading(","Theme.setText(","setTextFormat",
           "buildSubtabs(","drawListHeader(",".text =",".text=",".width =",".width=","autoSize"]
def method_body(src, name):
    i=src.find("function "+name+"(")
    if i<0: return None
    j=src.find("{", i); depth=0; k=j
    while k<len(src):
        if src[k]=="{": depth+=1
        elif src[k]=="}":
            depth-=1
            if depth==0: return src[j+1:k]
        k+=1
    return None
fail=0
for f in ["PipOS_InvPage.as","PipOS_DataPage.as","PipOS_RadioPage.as","PipOS_StatsPage.as"]:
    p=os.path.join(SRC,f); s=open(p,encoding="utf-8").read()
    ctor=method_body(s, os.path.splitext(f)[0])
    panels=method_body(s,"buildPanels")
    problems=[]
    if ctor is None: problems.append("no ctor")
    else:
        if "buildChrome(" in ctor: problems.append("ctor still calls buildChrome (must be buildPanels)")
        if "buildText(" in ctor: problems.append("ctor calls buildText directly")
    if panels is None: problems.append("no buildPanels()")
    else:
        for tok in FORBIDDEN:
            if tok in panels: problems.append("buildPanels contains '%s'"%tok)
    if method_body(s,"buildText") is None: problems.append("no buildText()")
    if "ensureText(" not in s: problems.append("no ensureText()")
    status="PASS" if not problems else "FAIL"
    if problems: fail+=1
    print("[%s] %s%s"%(status, f, "" if not problems else " -> "+"; ".join(problems)))
CREATE=["new TextField","Theme.tf(","Theme.mk(","Theme.heading("]
# WIDTH RULE (crash-2026-08-17-01-35-40): setting TextField.width on a POOLED, on-stage, text-bearing field
# forces DocView::Format -> ParagraphFormatter -> FindFont(NULL) AV. SetWidth is frame [4] of every FindFont
# crash. Every refresh/selection/tick handler below (pooled-field mutators) must be BOTH field-free AND
# width-free: move geometry by .x and clip with scrollRect, never .width. (One-time creation of a FRESH empty
# field before its .text -- buildText/buildPanels, PipList.render -- may set .width; word-wrap and right-aligned
# column boxes structurally require it. Only re-mutation on the refresh path crashes.)
WIDTHSET=[".width =",".width="]
GATE={"PipOS_DataPage.as":["renderDetail","onListSel","onObjectivesReady"],"PipOS_InvPage.as":["renderCard","onListSel","onRowClick","layoutHeader","applyEquip"],"pipos/Chrome.as":["onTick","onTabHit","acquireMenu","paintTabs","readSettings"]}
INFO={"PipOS_InvPage.as":["renderQuick","buildSubtabs"],"PipOS_DataPage.as":["buildSubtabs"],"PipOS_StatsPage.as":["buildSubtabs"]}
for f,ms in GATE.items():
    s2=open(os.path.join(SRC,f),encoding="utf-8").read()
    for m in ms:
        body=method_body(s2,m)
        if body is None: continue
        bad=[c for c in CREATE if c in body]
        badw=[w for w in WIDTHSET if w in body]
        if bad: fail+=1; print("[FAIL] %s::%s creates fields %s (render/selection gate)"%(f,m,bad))
        if badw: fail+=1; print("[FAIL] %s::%s sets TextField.width %s (SetWidth->FindFont crash; use .x + scrollRect)"%(f,m,badw))
        if not bad and not badw: print("[PASS] %s::%s field-free + width-free"%(f,m))
for f,ms in INFO.items():
    s2=open(os.path.join(SRC,f),encoding="utf-8").read()
    for m in ms:
        body=method_body(s2,m)
        if body and any(c in body for c in CREATE): print("[note] %s::%s still creates fields (residual)"%(f,m))
# PipList mutator handlers (NOT render) must stay width-free: position by .x, clip with scrollRect, never
# SetWidth on a text-bearing field (TextField::SetWidth -> DocView::Format -> FindFont(NULL) == hard CTD).
# NOTE (0.0.29): `render` is DELIBERATELY NOT in this list anymore. The auto-size root cause (crash-2026-08-17-
# 06-38-33) means render must now set an EXPLICIT width on each FRESH EMPTY cell BEFORE its text (autoSize="none"
# + width-before-text is the safe pattern; the auto-size resize DURING .text was the real vector). width-AFTER-
# text in render is still caught by RENDER_GEO_GATE below, and the AUTOSIZE_CREATE_GATE proves autoSize="none"
# precedes text. The pure mutators (tick/hover/select) keep the absolute width-forbid.
WIDTH_ONLY_GATE={"pipos/PipList.as":["onMarqTick","onRowOver","onRowOut","drawHover","selectIndex","onWheel"]}
for f,ms in WIDTH_ONLY_GATE.items():
    s2=open(os.path.join(SRC,f),encoding="utf-8").read()
    for m in ms:
        body=method_body(s2,m)
        if body is None: continue
        badw=[w for w in WIDTHSET if w in body]
        if badw: fail+=1; print("[FAIL] %s::%s sets TextField.width %s (SetWidth->FindFont crash; use .x + scrollRect)"%(f,m,badw))
        else: print("[PASS] %s::%s width-free"%(f,m))

# P0-A (crash-2026-08-17-04-38-01, TextField::SetY <- DocView::Format <- FindFont(NULL)): setting ANY geometry
# (.x/.y/.width/.height) on a field that ALREADY holds text forces a reformat -> FindFont crash in a PAGE's
# fragile ADDED_TO_STAGE loader-complete context. RULE for PAGE build methods: set ALL geometry on a fresh
# field BEFORE its text. PRECISE per-variable check: for each field variable, if a geometry setter on it
# appears AFTER a text set (`.text =` or `Theme.setText(v`) on the SAME variable, FAIL. (Multiple fields with
# geometry-before-their-own-text pass, because the check is per variable, not "any geometry after any text".)
# Scope = PAGE build methods only. Chrome.buildText is excluded: it attaches on a UI task with the font already
# resolved (not the fragile page loader-complete path) and legitimately reads .width to center/right-align its
# one-shot top-strip labels; the crash class is page loads via ProcessLoadQueue.
GEO_RE = re.compile(r'((?:this\.)?[A-Za-z_]\w*)\.(x|y|width|height)\s*=')
TEXT_RE = re.compile(r'((?:this\.)?[A-Za-z_]\w*)\.text\s*=')
SETTEXT_RE = re.compile(r'Theme\.setText\(\s*((?:this\.)?[A-Za-z_]\w*)')
BUILD_GATE={"PipOS_InvPage.as":["buildText","buildSubtabs"],"PipOS_DataPage.as":["buildText","buildSubtabs"],"PipOS_RadioPage.as":["buildText"],"PipOS_StatsPage.as":["buildText","buildSubtabs"]}
for f,ms in BUILD_GATE.items():
    s2=open(os.path.join(SRC,f),encoding="utf-8").read()
    for m in ms:
        body=method_body(s2,m)
        if body is None: continue
        text_at={}
        for mt in list(TEXT_RE.finditer(body))+list(SETTEXT_RE.finditer(body)):
            v=mt.group(1); text_at[v]=max(text_at.get(v,-1), mt.start())
        viol=[]
        for mg in GEO_RE.finditer(body):
            v=mg.group(1)
            if v in text_at and mg.start()>text_at[v]: viol.append("%s.%s after text"%(v,mg.group(2)))
        if viol: fail+=1; print("[FAIL] %s::%s geometry-AFTER-text %s (set geometry on the fresh field BEFORE setText; SetY/SetWidth->FindFont)"%(f,m,viol))
        else: print("[PASS] %s::%s geometry-before-text"%(f,m))

# P0 (0.0.26, crash: renderDetail SetY->FindFont on the DATA quest-click RENDER path): the geometry-after-text
# crash is NOT confined to build methods. Render/selection handlers reuse POOLED text-bearing fields (or freshly
# create+text row cells), so setting .y/.width/.height on a field AFTER its text is the SAME FindFont reformat on
# the render path. Gate the render/selection methods for geometry-after-text, EXCLUDING .x (the designated-safe
# reposition: right-align reads .width then sets .x). Same per-variable textual check as BUILD_GATE, .x dropped.
RENDER_GEO_GATE={"PipOS_DataPage.as":["renderDetail","onListSel","onObjectivesReady"],"PipOS_InvPage.as":["renderCard","onListSel","onRowClick"],"pipos/PipList.as":["render"]}
for f,ms in RENDER_GEO_GATE.items():
    s2=open(os.path.join(SRC,f),encoding="utf-8").read()
    for m in ms:
        body=method_body(s2,m)
        if body is None: continue
        text_at={}
        for mt in list(TEXT_RE.finditer(body))+list(SETTEXT_RE.finditer(body)):
            v=mt.group(1); text_at[v]=max(text_at.get(v,-1), mt.start())
        viol=[]
        for mg in GEO_RE.finditer(body):
            if mg.group(2)=="x": continue   # .x is the designated-safe reposition (right-align by width read)
            v=mg.group(1)
            if v in text_at and mg.start()>text_at[v]: viol.append("%s.%s after text"%(v,mg.group(2)))
        if viol: fail+=1; print("[FAIL] %s::%s geometry-AFTER-text %s (render/selection path; set .y/.w/.h BEFORE text or fix at creation; SetY/SetWidth->FindFont)"%(f,m,viol))
        else: print("[PASS] %s::%s render-path geometry-before-text"%(f,m))

# P0 (0.0.29 AUTO-SIZE ROOT CAUSE, crash-2026-08-17-06-38-33): Theme.tf()/Theme.mk() return AUTO-SIZE fields
# (autoSize=LEFT/CENTER/RIGHT per align). Setting .text on an auto-size field makes Scaleform RESIZE it ->
# internal TextField::SetWidth -> GetViewRect -> Format -> FindFont(NULL) == the crash, fired from the per-render
# mouse/key path (PipList.render creates FRESH cells every selection). There is NO literal `.width =` on that
# path -- the SetWidth is triggered by auto-size -- so the geometry/width gates alone can't see it. This gate
# catches the blind spot: a field FRESHLY CREATED via Theme.tf/Theme.mk/new TextField in a render/selection
# method and then given text (`.text =` or Theme.setText) MUST set .autoSize (to "none") on that field BEFORE
# the text. (Pooled fields set autoSize="none" once at creation in buildText and are only updated here, so this
# gate scopes to LOCALLY-CREATED fresh fields only.) buildSubtabs is a documented per-refresh field-creator
# residual (fixed-width would break variable-width tab layout) and stays in the INFO note, not this hard gate.
AUTOSIZE_RE = re.compile(r'((?:this\.)?[A-Za-z_]\w*)\.autoSize\s*=')
CREATE_VAR_RE = re.compile(r'\bvar\s+([A-Za-z_]\w*)\s*:\s*TextField\s*=\s*(?:Theme\.tf|Theme\.mk|new\s+TextField)')
AUTOSIZE_GATE={"pipos/PipList.as":["render"],"PipOS_DataPage.as":["renderDetail","onListSel","onObjectivesReady"],"PipOS_RadioPage.as":["renderInfo","onListSel"],"PipOS_InvPage.as":["renderCard","onListSel","onRowClick"]}
for f,ms in AUTOSIZE_GATE.items():
    s2=open(os.path.join(SRC,f),encoding="utf-8").read()
    for m in ms:
        body=method_body(s2,m)
        if body is None: continue
        created=set(mc.group(1) for mc in CREATE_VAR_RE.finditer(body))
        as_at={}
        for ma in AUTOSIZE_RE.finditer(body):
            v=ma.group(1); base=v[5:] if v.startswith("this.") else v
            as_at[base]=min(as_at.get(base,10**9), ma.start())
        viol=[]
        for mt in list(TEXT_RE.finditer(body))+list(SETTEXT_RE.finditer(body)):
            v=mt.group(1); base=v[5:] if v.startswith("this.") else v
            if base not in created: continue   # only fresh, locally-created (auto-size) fields
            if base not in as_at or as_at[base] > mt.start(): viol.append("%s texted without prior autoSize=none"%base)
        if viol: fail+=1; print("[FAIL] %s::%s AUTO-SIZE text %s (set autoSize=\"none\" on the fresh field BEFORE .text; auto-size resize on text = SetWidth->FindFont)"%(f,m,sorted(set(viol))))
        else: print("[PASS] %s::%s no fresh auto-size field texted"%(f,m))

# P0-A reposition-only gate: layoutHeader/applyEquip run on the refresh path and must NOT set .y/.height/.width
# on their text-bearing pooled fields (SetY/SetWidth = the FindFont crash frames). .x IS allowed (columns slide
# horizontally by .x; documented safe pattern). renderCard is NOT here -- it legitimately sets .y BEFORE text.
YHWSET=[".y =",".y=",".height =",".height=",".width =",".width="]
REPOS_GATE={"PipOS_InvPage.as":["layoutHeader","applyEquip"]}
for f,ms in REPOS_GATE.items():
    s2=open(os.path.join(SRC,f),encoding="utf-8").read()
    for m in ms:
        body=method_body(s2,m)
        if body is None: continue
        bad=[w for w in YHWSET if w in body]
        if bad: fail+=1; print("[FAIL] %s::%s sets %s (reposition-only handler; use .x + scrollRect, never .y/.height/.width)"%(f,m,bad))
        else: print("[PASS] %s::%s reposition-only (.x + scrollRect)"%(f,m))

# P2 (0.0.27, Chrome.buildText [EXT] badge): the badge SET .y AFTER setText -- the exact FindFont geometry-
# after-text pattern, stable ~26 builds only because the chrome's font is resolved at attach (its own task, not
# the fragile page loader-complete path). Normalized to geometry-before-text; now GATE EVERY Chrome method for
# .y/.width/.height-after-text (per-variable, same textual check as the page gates), keeping .x EXEMPT (the
# right-align width-read reposition, e.g. topC/topR/badge). Chrome.buildText is deliberately NOT in the PAGE
# BUILD_GATE (different, non-fragile attach context) so this is its own dedicated coverage.
FUNC_RE = re.compile(r'function\s+([A-Za-z_]\w*)\s*\(')
chrome_src = open(os.path.join(SRC,"pipos","Chrome.as"),encoding="utf-8").read()
for fm in FUNC_RE.finditer(chrome_src):
    m = fm.group(1)
    body = method_body(chrome_src, m)
    if body is None: continue
    text_at={}
    for mt in list(TEXT_RE.finditer(body))+list(SETTEXT_RE.finditer(body)):
        v=mt.group(1); text_at[v]=max(text_at.get(v,-1), mt.start())
    if not text_at: continue   # no text set in this method -> geometry can't be "after text"
    viol=[]
    for mg in GEO_RE.finditer(body):
        if mg.group(2)=="x": continue   # .x is the designated-safe reposition (right-align by width read)
        v=mg.group(1)
        if v in text_at and mg.start()>text_at[v]: viol.append("%s.%s after text"%(v,mg.group(2)))
    if viol: fail+=1; print("[FAIL] pipos/Chrome.as::%s geometry-AFTER-text %s (set .y/.w/.h BEFORE setText; FindFont geometry-after-text)"%(m,viol))
    else: print("[PASS] pipos/Chrome.as::%s geometry-before-text"%m)

# ============================================================================================
# 0.0.31 POOLING INVARIANT (crash class (2): a script geometry-write on a FRESH/EMPTY TextField inside
# INTERACTION dispatch -> SetWidth -> Format -> FindFont(NULL); glyph-independent, so sanitize can't stop
# it). Structural fix = full pooling: every field is created and given ALL geometry ONCE in the build window
# (buildPool / buildText / buildSubtabs pool-builder / buildPanels / ctor), and every interaction-reachable
# method is UPDATE-ONLY. This gate FLAGS, inside the handler methods below: (a) any field CREATION
# (Theme.tf/Theme.mk/Theme.heading/new TextField), and (b) any `.x/.y/.width/.height/.autoSize =` write on a
# TextField-typed variable (instance field, local :TextField, or an indexed element of a known TextField
# Array). Pool-builder methods are NOT in the handler list, so their legitimate creation/geometry is exempt.
NEW_CREATE=["Theme.tf(","Theme.mk(","Theme.heading(","new TextField"]
NEW_PROPS="(?:x|y|width|height|autoSize)"
NEW_HANDLERS={
  "pipos/PipList.as":["render","onRowClick","onRowOver","onRowOut","onWheel","handleKey","selectIndex","drawHover","onMarqTick","pressSelected","renderCols","renderLabel","renderSep","styleField",
                      # 0.0.43 selection-pulse glow redraw (graphics/alpha only, reachable from onMarqTick)
                      "drawSelGlow",
                      # 0.0.33: previously-ungated interaction-reachable PipList entry points (audit note A1)
                      "setRenderRows","setClipHeight","columnGeom","selectIndexSilent",
                      # 0.0.36 FIS folders: folder-header caret drawer (graphics-only, reachable from renderSep)
                      "drawFolderCaret"],
  # 0.0.33 (audit note A1): the 0.0.32 gate lists OMITTED these interaction-reachable methods, so a
  # violation injected into e.g. doExpand still passed. All INV interaction-reachable methods (the sort/
  # expand/title machinery + the new item-card fill helpers) are now gated update-only. buildText / the
  # pool/build-window methods are deliberately NOT listed (they legitimately create fields + set geometry).
  "PipOS_InvPage.as":["onPipboyChangeEvent","onListSel","onListPress","renderCard","renderQuick","doCycleDamage","doFav","doDrop","doInspect","doSort","layoutHeader","applyEquip","updateSubtabs","onSubtabClick","onListSelectionChangeCallback","onKey",
                      # 0.0.32 methods the audit found ungated:
                      "onHeaderClick","doExpand","onExpandBtn","onExpandTick","drawSortIndicator","updateInvTitle","rebuildList","applySort",
                      # 0.0.33 new item-card helpers (all pure string derivation, but gated per A1):
                      "selRow","cardName","stripMarkers","cardSubStr","cardLegStr","cardPairsFor","cardDescStr",
                      # 0.0.34 QA-box (A) + tooltip (B) interaction-reachable methods. buildTooltip is a POOL
                      # BUILDER (called once from buildText) and is deliberately NOT listed -- it legitimately
                      # creates fields + bakes geometry. Everything below is update-only (text/visible/graphics +
                      # Sprite-container .x/.y). The ico* + drawQAIcon glyph helpers are graphics-only.
                      "renderQuick","drawQAIcon","icoWeapon","icoApparel","icoAid","icoAmmo","icoNote","icoJunk","icoMisc",
                      "onListHover","onQAOver","onQAOut","hideTooltip","showTooltip","drawTipPanel","positionTip",
                      "onMouseMove","tipSubStr","tipLinesFor","onQAClick","favCategory","findDisplayIndexByFormID",
                      # INSPECT overlay interaction-reachable methods (all update-only: text/visible/textColor +
                      # graphics + Sprite-container transforms). buildInspect is the POOL BUILDER (called once from
                      # buildText) and is deliberately NOT listed -- it legitimately creates fields + bakes geometry.
                      "enterInspect","exitInspect","cycleInspect","onInspectKey","onInspectWheel","onInspectTick",
                      "renderInspect","renderInspectEmblem","inspectStatLines",
                      # 0.0.36 FIS/FallUI tag FOLDERS: parse + group + collapse-toggle interaction-reachable methods.
                      # All pure string/array derivation or state flips (no fields, no geometry); gated per crash law.
                      "itemAdapter","parseTag","stripPUA","isPlausibleTag","ltrim","trimStr","groupPairs",
                      "isFolderCollapsed","setFolderCollapsed","onFolderToggle",
                      # 0.0.42 tag-strip + folder humanize/category + collapsed-default selection helpers. All pure
                      # string/array derivation or state flips (no fields, no geometry); gated per crash law.
                      "stripTags","folderBucket","isMeleeTag","hasSub","hasAny","folderLabel","humanize",
                      "openFolderForFormID",
                      # 0.0.43 QA short-name derivation (pure string; no fields/geometry)
                      "qaShortName"],
  "PipOS_DataPage.as":["onPipboyChangeEvent","onListSel","onListPress","onObjectivesReady","renderDetail","doSummary","doTrack","doMap","updateSubtabs","onSubtabClick","onKey"],
  "PipOS_RadioPage.as":["onPipboyChangeEvent","onListSel","onListPress","renderInfo","doTune","onTick","onKey",
                        # parity: MHz flavor derivation (pure string; no fields/geometry) reached from renderInfo
                        "stationMHz"],
  # 0.0.41 custom Stats page (replaces vanilla stock). All render/handler methods are update-only: setText/
  # textColor/visible + Shape graphics (meter frames/bars, SPECIAL tiles, limb chips, panel borders redraw
  # freely -- not TextField geometry). buildPanels/buildText/buildSubtabs (pool builders) are NOT listed.
  "PipOS_StatsPage.as":["onPipboyChangeEvent","renderStatus","renderLevel","listHeaders","onListSel","onSubtabClick",
                        "updateSubtabs","acquireMenu","doStim","doRad","doToggleFigure","onLimbClick","onKey",
                        "specialAdapter","perkAdapter"],
}
# indexed TextField Arrays (handlers must not write geometry on their elements either)
TF_ARRAYS={
  "PipOS_InvPage.as":["_cardPairL","_cardPairV","_hdr","_qCount","_qNum","_qName","_equipVal","_subFields","_tipRowL","_tipRowV","_insStatL","_insStatV","_insModRows"],
  "PipOS_DataPage.as":["_objRows","_subFields"],
  "PipOS_RadioPage.as":[],
  "PipOS_StatsPage.as":["_mLabel","_mVal","_spVal","_spLbl","_limbName","_efRowL","_efRowR","_subFields"],
  "pipos/PipList.as":[],
}
TF_FIELD_DECL=re.compile(r'(?:private|public|protected|internal)\s+var\s+(\w+)\s*:\s*TextField\b')
TF_LOCAL_DECL=re.compile(r'\bvar\s+(\w+)\s*:\s*TextField\b')
for f,ms in NEW_HANDLERS.items():
    path=os.path.join(SRC,*f.split("/"))
    s2=open(path,encoding="utf-8").read()
    tf_fields=set(TF_FIELD_DECL.findall(s2))
    arrs=TF_ARRAYS.get(f,[])
    for m in ms:
        body=method_body(s2,m)
        if body is None: continue
        prob=[]
        for tok in NEW_CREATE:
            if tok in body: prob.append("creates field %s"%tok)
        names=set(tf_fields)|set(TF_LOCAL_DECL.findall(body))
        for nm in names:
            if re.search(r'(?:this\.)?'+re.escape(nm)+r'\.'+NEW_PROPS+r'\s*=', body):
                prob.append("geometry write on TextField %s"%nm)
        for arr in arrs:
            if re.search(r'(?:this\.)?'+re.escape(arr)+r'\[[^\]]*\]\.'+NEW_PROPS+r'\s*=', body):
                prob.append("geometry write on TextField-array %s[]"%arr)
        if prob: fail+=1; print("[FAIL] %s::%s POOLING INVARIANT -> %s (create fields + set geometry ONCE in the build window; handlers are update-only)"%(f,m,"; ".join(sorted(set(prob)))))
        else: print("[PASS] %s::%s pooled/update-only"%(f,m))

print("\nCTOR-TEXT CHECK:", "ALL PASS" if fail==0 else "%d FAIL"%fail)
sys.exit(1 if fail else 0)
