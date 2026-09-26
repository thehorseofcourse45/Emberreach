"""Generate the art-asset manifest: ASSET_MANIFEST.html (tracker) + asset_manifest.csv.

Paths are resolved relative to this script, so it can live anywhere inside the
project. Outputs are written next to the script (project root); preview images
are referenced with a relative path computed from the HTML location, so the
manifest works both at the project root and inside assets/manifest/.

Status model:
  - delivered : file exists on disk (scanned at generation time), locked green
  - ticked    : missing on disk but clicked in the browser (localStorage)
  - missing   : nothing on disk, not ticked

Regenerate any time:  python gen_assets_manifest.py
"""
import json, os, csv, html

BASE = os.path.dirname(os.path.abspath(__file__))
DATA = os.path.join(BASE, "data")
ASSETS = os.path.join(BASE, "assets")
OUT_HTML = os.path.join(BASE, "ASSET_MANIFEST.html")
OUT_CSV = os.path.join(BASE, "asset_manifest.csv")

# Relative prefix from the HTML file to the assets dir (works at root or in assets/manifest/)
PREVIEW_BASE = os.path.relpath(ASSETS, os.path.dirname(OUT_HTML)).replace("\\", "/") + "/"

def load(n):
    p = os.path.join(DATA, n)
    return json.load(open(p, encoding="utf-8")) if os.path.exists(p) else {}

def keys(n):
    return [k for k in load(n).keys() if not k.startswith("_")]

items = load("items.json"); skills = load("skills.json"); monsters = load("monsters.json")
areas = load("areas.json"); dungeons = load("dungeons.json"); prayers = load("prayers.json")
pets = load("pets.json"); familiars = load("familiars.json"); obstacles = load("obstacles.json")
constellations = load("constellations.json")

SLOTS = {"helmet":"Helmet","platebody":"Platebody","platelegs":"Platelegs","boots":"Boots","gloves":"Gloves",
 "cape":"Cape","amulet":"Amulet","ring":"Ring","weapon":"Weapon","shield":"Shield","quiver":"Quiver",
 "summon_1":"Summoning (slot 1)","summon_2":"Summoning (slot 2)","passive":"Passive","consumable":"Consumable"}
CURRENCIES = {"gp":"Gold Pieces","slayer_coins":"Slayer Coins","prayer_points":"Prayer Points",
 "stardust":"Stardust","golden_stardust":"Golden Stardust","raid_coins":"Raid Coins","abyssal_coins":"Abyssal Coins"}
STATUS = {"stun":"Stun / Freeze","sleep":"Sleep","burn":"Burn","poison":"Poison","bleed":"Bleed","slow":"Slow",
 "crystallize":"Crystallize","curse":"Curse","corruption":"Corruption"}

def nm(d, i):
    return (d.get(i, {}) or {}).get("name", i)

def entry(tmpl, i, size, prio, name, extra=""):
    return {"rel": tmpl.replace("{id}", i), "id": i, "size": size, "prio": prio, "name": name, "extra": extra}

groups = []

skill_ids = sorted([k for k in skills.keys() if not k.startswith("_")], key=lambda k: skills[k].get("order", 999))
groups.append(("Items", "icons/items/{id}.png", "32x32", "P0",
    "One per item. Themed sheets are fine, each sheet works on arrival.",
    [entry("icons/items/{id}.png", i, "32x32", "P0",
        nm(items, i), items.get(i, {}).get("item_type", "")) for i in keys("items.json")]))
groups.append(("Skills, combat", "icons/skills/{id}.png", "128x128", "P0",
    "The 9 combat skills in canonical order. Delivered at 128x128; any square size works, the UI scales.",
    [entry("icons/skills/{id}.png", i, "128x128", "P0", nm(skills, i), "combat") for i in skill_ids if skills[i].get("category") == "combat"]))
groups.append(("Skills, non-combat", "icons/skills/{id}.png", "128x128", "P0",
    "The %d non-combat skills in canonical order. Any square size works, the UI scales." % (len(skill_ids) - sum(1 for i in skill_ids if skills[i].get("category") == "combat")),
    [entry("icons/skills/{id}.png", i, "128x128", "P0", nm(skills, i), "non-combat") for i in skill_ids if skills[i].get("category") != "combat"]))
groups.append(("Monsters", "sprites/monsters/{id}.png", "96x96", "P0",
    "Battle sprite or portrait per monster, transparent, centred.",
    [entry("sprites/monsters/{id}.png", i, "96x96", "P0", nm(monsters, i),
        "Lv %s" % monsters[i].get("combat_level", "?")) for i in keys("monsters.json")]))
groups.append(("Currencies", "icons/currencies/{id}.png", "24x24", "P0", "Top-bar currency icons.",
    [entry("icons/currencies/{id}.png", i, "24x24", "P0", CURRENCIES.get(i, i)) for i in CURRENCIES]))
groups.append(("Equipment slots", "icons/slots/{id}.png", "28x28", "P1", "Equipment panel slot icons.",
    [entry("icons/slots/{id}.png", i, "28x28", "P1", SLOTS[i]) for i in SLOTS]))
groups.append(("Areas", "icons/areas/{id}.png", "64x64", "P1", "Combat and slayer area icons.",
    [entry("icons/areas/{id}.png", i, "64x64", "P1", nm(areas, i), areas[i].get("type", "")) for i in keys("areas.json")]))
groups.append(("Dungeons", "icons/dungeons/{id}.png", "64x64", "P1", "Dungeon icons.",
    [entry("icons/dungeons/{id}.png", i, "64x64", "P1", nm(dungeons, i)) for i in keys("dungeons.json")]))
groups.append(("Prayers", "icons/prayers/{id}.png", "32x32", "P1", "Prayer icons.",
    [entry("icons/prayers/{id}.png", i, "32x32", "P1", nm(prayers, i),
        "Lv %s" % prayers[i].get("level", "?")) for i in keys("prayers.json")]))
groups.append(("Pets", "icons/pets/{id}.png", "32x32", "P1", "Pet icons.",
    [entry("icons/pets/{id}.png", i, "32x32", "P1", nm(pets, i),
        pets[i].get("source_skill", "")) for i in keys("pets.json")]))
groups.append(("Familiars", "icons/familiars/{id}.png", "32x32", "P2", "Summoning familiar icons.",
    [entry("icons/familiars/{id}.png", i, "32x32", "P2", nm(familiars, i),
        "Tier %s" % familiars[i].get("tier", "?")) for i in keys("familiars.json")]))
groups.append(("Agility obstacles", "icons/obstacles/{id}.png", "32x32", "P2", "Obstacle and pillar icons.",
    [entry("icons/obstacles/{id}.png", i, "32x32", "P2", nm(obstacles, i)) for i in keys("obstacles.json")]))
groups.append(("Constellations", "icons/constellations/{id}.png", "48x48", "P2", "Constellation icons.",
    [entry("icons/constellations/{id}.png", i, "48x48", "P2", nm(constellations, i)) for i in keys("constellations.json")]))
groups.append(("Status effects", "icons/status/{id}.png", "24x24", "P2", "Combat status-effect badges.",
    [entry("icons/status/{id}.png", i, "24x24", "P2", STATUS.get(i, i)) for i in STATUS]))

UI = [
 ("ui/panel_9slice.png", "Panel frame (9-slice)", "48x48", "P0", "12 px corner margins"),
 ("ui/button_9slice.png", "Button (9-slice)", "32x32", "P0", "8 px margins"),
 ("ui/progress_bg.png", "Progress bar track", "16x16", "P0", "tileable"),
 ("ui/progress_fill.png", "Progress bar fill", "16x16", "P0", "tileable"),
 ("icons/icon.svg", "App icon", "256x256", "P0", ""),
 ("ui/button_hover.png", "Button hover", "32x32", "P1", "9-slice"),
 ("ui/hp_fill_player.png", "Player HP fill", "16x16", "P1", "combat bar"),
 ("ui/hp_fill_enemy.png", "Enemy HP fill", "16x16", "P1", "combat bar"),
 ("fonts/ui.ttf", "UI font", "-", "P1", "optional"),
 ("ui/tab_active.png", "Active tab", "64x28", "P2", ""),
 ("ui/tab_inactive.png", "Inactive tab", "64x28", "P2", ""),
 ("ui/toast.png", "Notification toast", "48x32", "P2", "9-slice"),
 ("ui/scrollbar.png", "Scrollbar grabber", "12x24", "P2", ""),
 ("ui/logo.png", "Title logo", "512x128", "P2", ""),
]

def delivered(rel):
    return os.path.exists(os.path.join(ASSETS, rel.replace("/", os.sep)))

# ---------------- CSV ----------------
rows = []
for _t, _tpl, _s, _p, _n, ents in groups:
    for e in ents:
        rows.append([e["rel"], e["rel"].split("/")[0], e["id"], e["size"], e["prio"], e["name"],
                     "delivered" if delivered(e["rel"]) else "missing"])
for p, n, s, pr, note in UI:
    rows.append([p, "ui", os.path.basename(p), s, pr, n, "delivered" if delivered(p) else "missing"])

total = len(rows)
ndone = sum(1 for r in rows if r[6] == "delivered")
rem = {p: sum(1 for r in rows if r[4] == p and r[6] == "missing") for p in ("P0", "P1", "P2")}

with open(OUT_CSV, "w", newline="", encoding="utf-8") as f:
    w = csv.writer(f)
    w.writerow(["relative_path", "category", "id", "size", "priority", "name", "status"])
    w.writerows(rows)

CSS = """
:root{--bg:#121512;--panel:#1a1e1b;--panel2:#212723;--ink:#eef2ec;--muted:#9aa79d;--faint:#71806f;
--line:#2a332c;--line2:#222a25;--acc:#a9e05b;--accdim:rgba(169,224,91,.14);
--p0:#e07a6e;--p1:#dfa558;--p2:#9aa79d;--ok:var(--acc)}
*{box-sizing:border-box}
html{scroll-behavior:smooth}
body{margin:0;background:
 radial-gradient(1100px 640px at 88% -8%,rgba(169,224,91,.06),transparent 60%),
 radial-gradient(900px 600px at -10% 12%,rgba(169,224,91,.03),transparent 55%),
 var(--bg);
 color:var(--ink);font:15px/1.55 "Bricolage Grotesque","Segoe UI",system-ui,sans-serif}
a{color:inherit}
.mono{font-family:"JetBrains Mono",Consolas,ui-monospace,monospace}
.wrap{max-width:1460px;margin:0 auto;padding:0 24px}

/* ---------- masthead ---------- */
header{padding:44px 0 26px;border-bottom:1px solid var(--line)}
.mh-top{display:flex;justify-content:space-between;align-items:flex-end;gap:24px;flex-wrap:wrap}
.eyebrow{font-family:"JetBrains Mono",Consolas,monospace;font-size:.72rem;letter-spacing:.14em;
text-transform:uppercase;color:var(--acc);margin-bottom:10px}
h1{margin:0;font-size:clamp(2.1rem,4vw,3.1rem);line-height:1.02;font-weight:700;letter-spacing:-.02em}
.lede{color:var(--muted);max-width:640px;margin:12px 0 0;font-size:.95rem}
.lede code{font-family:"JetBrains Mono",Consolas,monospace;font-size:.82em;background:var(--panel);
border:1px solid var(--line);padding:1px 6px;border-radius:5px;color:#cfe0c8}
.bigstat{text-align:right}
.big{display:block;font-family:"JetBrains Mono",Consolas,monospace;font-weight:700;
font-size:clamp(3rem,6vw,4.6rem);line-height:.95;color:var(--acc);letter-spacing:-.03em;font-variant-numeric:tabular-nums}
.bigsub{color:var(--muted);font-size:.82rem}
.pbar{height:5px;border-radius:4px;background:var(--panel2);margin:26px 0 14px;overflow:hidden}
.pbar i{display:block;height:100%;background:linear-gradient(90deg,#7fbf45,var(--acc));border-radius:4px}
.chips{display:flex;gap:8px;flex-wrap:wrap}
.chip{border:1px solid var(--line);background:var(--panel);border-radius:999px;padding:4px 12px;
font-size:.78rem;color:var(--muted);font-family:"JetBrains Mono",Consolas,monospace}
.chip b{color:var(--ink);font-weight:600}
.chip.acc{border-color:rgba(169,224,91,.35)}
.chip.acc b{color:var(--acc)}
.jumps{display:flex;gap:6px;flex-wrap:wrap;margin-top:18px}
.jumps a{font-size:.76rem;color:var(--muted);text-decoration:none;border:1px solid var(--line);
border-radius:7px;padding:4px 9px;background:rgba(26,30,27,.5)}
.jumps a:hover{color:var(--ink);border-color:var(--acc)}
.jumps a b{color:var(--faint);font-weight:400;font-family:"JetBrains Mono",Consolas,monospace;font-size:.7rem}

/* ---------- toolbar ---------- */
.bar{position:sticky;top:0;z-index:5;background:rgba(18,21,18,.93);backdrop-filter:blur(8px);
border-bottom:1px solid var(--line);padding:10px 0}
.bar .wrap{display:flex;gap:10px;align-items:center;flex-wrap:wrap}
input[type=search]{background:#0e120f;border:1px solid var(--line);color:var(--ink);border-radius:8px;
padding:7px 11px;min-width:280px;font-size:.88rem;font-family:inherit}
input[type=search]:focus{outline:none;border-color:var(--acc)}
.btn{border:1px solid var(--line);background:var(--panel);color:var(--muted);border-radius:8px;
padding:6px 13px;font-size:.8rem;cursor:pointer;font-family:"JetBrains Mono",Consolas,monospace}
.btn:hover{color:var(--ink)}
.btn.on{color:#101408;background:var(--acc);border-color:var(--acc);font-weight:700}
label.chip{cursor:pointer;display:flex;align-items:center;gap:6px}
label.chip input{accent-color:var(--acc)}
.count{color:var(--muted);font-size:.78rem;margin-left:auto;font-family:"JetBrains Mono",Consolas,monospace}

/* ---------- sections ---------- */
section{padding:34px 0 10px;border-bottom:1px solid var(--line2)}
.sec-head{display:flex;justify-content:space-between;align-items:baseline;gap:18px;flex-wrap:wrap}
h2{font-size:1.35rem;margin:0;letter-spacing:-.01em}
.sec-meta{display:flex;align-items:center;gap:12px}
.don{font-family:"JetBrains Mono",Consolas,monospace;font-size:.76rem;color:var(--muted);white-space:nowrap}
.mini{width:120px;height:4px;border-radius:3px;background:var(--panel2);overflow:hidden}
.mini i{display:block;height:100%;background:var(--acc);border-radius:3px}
.note{color:var(--muted);font-size:.85rem;margin:6px 0 0;max-width:820px}
.note code{font-family:"JetBrains Mono",Consolas,monospace;font-size:.8em;background:var(--panel);
border:1px solid var(--line);padding:1px 6px;border-radius:5px;color:#cfe0c8}

/* ---------- tiles ---------- */
.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(330px,1fr));gap:10px;margin:16px 0 20px}
.tile{display:flex;gap:12px;align-items:center;background:var(--panel);border:1px solid var(--line);
border-radius:10px;padding:9px 11px;cursor:pointer;position:relative;transition:border-color .15s,transform .15s}
.tile:hover{border-color:var(--acc);transform:translateY(-1px)}
.tile:active{transform:translateY(0) scale(.995)}
.tile.done{opacity:.55}
.tile.is-disk{border-color:rgba(169,224,91,.4);cursor:default}
.tile.is-disk:hover{transform:none}
.thumb{width:46px;height:46px;flex:0 0 46px;border-radius:8px;border:1px solid var(--line2);overflow:hidden;
display:flex;align-items:center;justify-content:center;
background:repeating-conic-gradient(#1c221e 0% 25%,#232a25 0% 50%) 50%/12px 12px}
.thumb img{max-width:100%;max-height:100%;image-rendering:pixelated}
.meta{min-width:0;flex:1}
.fname{font-family:"JetBrains Mono",Consolas,monospace;font-size:.72rem;color:#c4d6c2;word-break:break-all}
.dname{font-size:.94rem;margin-top:2px;font-weight:600}
.sub2{color:var(--muted);font-size:.72rem;margin-top:3px;display:flex;align-items:center;gap:7px;font-family:"JetBrains Mono",Consolas,monospace}
.pr{font-weight:700;font-size:.68rem}
.pr.p0{color:var(--p0)}.pr.p1{color:var(--p1)}.pr.p2{color:var(--p2)}
.st{font-size:.64rem;font-weight:700;letter-spacing:.06em;text-transform:uppercase;
border-radius:999px;padding:1px 8px;margin-left:auto;white-space:nowrap}
.st-ok{background:var(--accdim);color:var(--acc)}
.st-tick{background:rgba(223,165,88,.16);color:var(--p1)}
.st-miss{background:rgba(154,167,157,.1);color:var(--faint)}

footer{padding:30px 0 60px;color:var(--muted);font-size:.84rem}
footer code{font-family:"JetBrains Mono",Consolas,monospace;font-size:.8em;background:var(--panel);
border:1px solid var(--line);padding:1px 6px;border-radius:5px;color:#cfe0c8}
@media (max-width:640px){
 .mh-top{align-items:flex-start;flex-direction:column}
 .bigstat{text-align:left}
 .grid{grid-template-columns:1fr}
 input[type=search]{min-width:0;flex:1}
}
"""

JS = """
var store={};
try{store=JSON.parse(localStorage.getItem('melvor_assets')||'{}')}catch(e){store={}}
function save(){try{localStorage.setItem('melvor_assets',JSON.stringify(store))}catch(e){}}
function isDone(t){return t.dataset.state==='delivered'||!!store[t.dataset.rel]}
function setBadge(t){
  var st=t.querySelector('.st'); if(!st) return;
  if(t.dataset.state==='delivered'){st.textContent='on disk';st.className='st st-ok';}
  else if(store[t.dataset.rel]){st.textContent='ticked';st.className='st st-tick';}
  else {st.textContent='missing';st.className='st st-miss';}
}
function refreshMasthead(){
  var tk=0; Object.keys(store).forEach(function(k){ if(store[k]) tk++; });
  var el=document.getElementById('ticked'); if(el) el.textContent=tk;
}
function refreshSection(sec){
  var total=+sec.dataset.total, disk=+sec.dataset.disk, tick=0;
  sec.querySelectorAll('.tile').forEach(function(t){
    if(t.dataset.state!=='delivered'&&store[t.dataset.rel]) tick++;
  });
  var done=disk+tick;
  var f=sec.querySelector('.mini i'); if(f) f.style.width=(total?100*done/total:0)+'%';
  var d=sec.querySelector('.don'); if(d) d.textContent=done+' / '+total;
}
function apply(){
  var q=document.getElementById('q').value.toLowerCase().trim();
  var on=document.querySelector('.btn.on');
  var pr=on?on.dataset.pr:'all';
  var hideDone=document.getElementById('hd').checked;
  var shown=0;
  document.querySelectorAll('section').forEach(function(sec){
    var vis=0;
    sec.querySelectorAll('.tile').forEach(function(t){
      var hitText=(q===''||t.dataset.rel.toLowerCase().indexOf(q)>=0||t.dataset.name.toLowerCase().indexOf(q)>=0);
      var hitPr=(pr==='all'||t.dataset.pr===pr);
      var hitDone=!(hideDone&&isDone(t));
      var ok=hitText&&hitPr&&hitDone;
      t.style.display=ok?'':'none';
      if(ok){vis++;shown++;}
    });
    var g=sec.querySelector('.grid'); if(g) g.style.display=vis?'':'none';
    sec.querySelector('h2').style.display=vis?'':'none';
    var sh=sec.querySelector('.sec-head'); if(sh) sh.style.display=vis?'':'none';
    var n=sec.querySelector('.note'); if(n) n.style.display=vis?'':'none';
  });
  document.getElementById('count').textContent=shown+' shown';
}
window.addEventListener('DOMContentLoaded',function(){
  document.querySelectorAll('.tile').forEach(function(t){
    if(store[t.dataset.rel]) t.classList.add('done');
    else if(t.dataset.state==='delivered') t.classList.add('done','is-disk');
    setBadge(t);
    t.addEventListener('click',function(){
      if(t.dataset.state==='delivered') return;
      var k=t.dataset.rel;
      if(store[k]){delete store[k];t.classList.remove('done')}
      else {store[k]=1;t.classList.add('done')}
      setBadge(t); save();
      var sec=t.closest('section'); if(sec) refreshSection(sec);
      refreshMasthead(); apply();
    });
  });
  document.querySelectorAll('section').forEach(refreshSection);
  document.getElementById('q').addEventListener('input',apply);
  document.querySelectorAll('.btn').forEach(function(b){
    b.addEventListener('click',function(){
      document.querySelectorAll('.btn').forEach(function(x){x.classList.remove('on')});
      b.classList.add('on');apply();
    });
  });
  document.getElementById('hd').addEventListener('change',apply);
  refreshMasthead(); apply();
});
"""

def tile(e):
    src = PREVIEW_BASE + e["rel"]
    ok = delivered(e["rel"])
    extra = " / %s" % e["extra"] if e["extra"] else ""
    return ('<div class="tile" data-rel="%s" data-name="%s" data-pr="%s" data-state="%s">'
            '<div class="thumb"><img src="%s" alt="" loading="lazy" onerror="this.remove()"></div>'
            '<div class="meta"><div class="fname">%s</div>'
            '<div class="dname">%s</div>'
            '<div class="sub2"><span class="pr %s">%s</span><span>%s</span><span>%s</span><span class="st"></span></div></div></div>') % (
        html.escape(e["rel"]), html.escape(e["name"].lower()), e["prio"],
        "delivered" if ok else "missing", html.escape(src),
        html.escape(e["rel"]), html.escape(e["name"]), e["prio"].lower(), e["prio"], e["size"], html.escape(extra))

out = []
out.append('<!DOCTYPE html><html lang="en"><head><meta charset="utf-8">')
out.append('<meta name="viewport" content="width=device-width, initial-scale=1">')
out.append('<title>Melvor Clone - Art Asset Manifest</title>')
out.append('<link rel="preconnect" href="https://fonts.googleapis.com">')
out.append('<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>')
out.append('<link href="https://fonts.googleapis.com/css2?family=Bricolage+Grotesque:opsz,wght@12..96,400..800&family=JetBrains+Mono:wght@400;600;700&display=swap" rel="stylesheet">')
out.append('<style>%s</style></head><body>' % CSS)

# masthead
pct = 100.0 * ndone / max(total, 1)
out.append('<header><div class="wrap">')
out.append('<div class="mh-top"><div>')
out.append('<div class="eyebrow">Melvor clone / art production tracker</div>')
out.append('<h1>Asset Manifest</h1>')
out.append('<p class="lede">Every art file the game loads, matched to <code>res://data/*.json</code> ids. '
           'Files already in <code>assets/</code> are marked <b>on disk</b> and locked; the rest can be '
           'clicked to tick them off. Ticks are saved in this browser and survive regeneration.</p>')
out.append('</div><div class="bigstat"><span class="big">%d%%</span><span class="bigsub">%d of %d files on disk</span></div></div>' % (round(pct), ndone, total))
out.append('<div class="pbar"><i style="width:%.1f%%"></i></div>' % pct)
out.append('<div class="chips"><span class="chip acc">delivered <b>%d</b></span>'
           '<span class="chip">ticked <b id="ticked">0</b></span>'
           '<span class="chip">P0 left <b>%d</b></span><span class="chip">P1 left <b>%d</b></span>'
           '<span class="chip">P2 left <b>%d</b></span></div>' % (ndone, rem["P0"], rem["P1"], rem["P2"]))
out.append('<nav class="jumps">')
out.append('<a href="#sec-ui">UI kit <b>%d</b></a>' % len(UI))
for gi, (title, tmpl, size, prio, note, ents) in enumerate(groups):
    out.append('<a href="#sec-%d">%s <b>%d</b></a>' % (gi + 1, html.escape(title), len(ents)))
out.append('</nav>')
out.append('</div></header>')

# toolbar
out.append('<div class="bar"><div class="wrap">')
out.append('<input id="q" type="search" placeholder="Filter by file name or item name">')
out.append('<button class="btn on" data-pr="all">All</button><button class="btn" data-pr="P0">P0</button>'
           '<button class="btn" data-pr="P1">P1</button><button class="btn" data-pr="P2">P2</button>')
out.append('<label class="chip"><input id="hd" type="checkbox"> hide done</label>')
out.append('<span class="count" id="count"></span></div></div>')

out.append('<main class="wrap">')

# UI kit section first
uione = sum(1 for p, n, s, pr, note in UI if delivered(p))
out.append('<section id="sec-ui" data-total="%d" data-disk="%d">' % (len(UI), uione))
out.append('<div class="sec-head"><h2>UI kit</h2><div class="sec-meta"><span class="don">%d / %d</span>'
           '<span class="mini"><i style="width:%.0f%%"></i></span></div></div>'
           % (uione, len(UI), 100.0 * uione / max(len(UI), 1)))
out.append('<p class="note">Build these first, they reskin every panel, button and bar at once. '
           'Panel and button are 9-slice: keep the listed corner margins clean. '
           '<code>res://assets/ui/</code></p>')
out.append('<div class="grid">')
for p, n, s, pr, note in UI:
    src = PREVIEW_BASE + p
    ex = (" / " + note) if note else ""
    ok = delivered(p)
    out.append('<div class="tile" data-rel="%s" data-name="%s" data-pr="%s" data-state="%s">'
               '<div class="thumb"><img src="%s" alt="" loading="lazy" onerror="this.remove()"></div>'
               '<div class="meta"><div class="fname">%s</div><div class="dname">%s</div>'
               '<div class="sub2"><span class="pr %s">%s</span><span>%s</span><span>%s</span><span class="st"></span></div></div></div>'
               % (html.escape(p), html.escape(n.lower()), pr, "delivered" if ok else "missing", html.escape(src),
                  html.escape(p), html.escape(n), pr.lower(), pr, s, html.escape(ex)))
out.append('</div></section>')

# data-driven groups
for gi, (title, tmpl, size, prio, note, ents) in enumerate(groups):
    gdone = sum(1 for e in ents if delivered(e["rel"]))
    out.append('<section id="sec-%d" data-total="%d" data-disk="%d">' % (gi + 1, len(ents), gdone))
    out.append('<div class="sec-head"><h2>%s</h2><div class="sec-meta"><span class="don">%d / %d</span>'
               '<span class="mini"><i style="width:%.0f%%"></i></span></div></div>'
               % (html.escape(title), gdone, len(ents), 100.0 * gdone / max(len(ents), 1)))
    out.append('<p class="note">%s &nbsp <code>res://assets/%s</code></p>'
               % (html.escape(note), html.escape(tmpl.replace("{id}", "&lt;id&gt;"))))
    out.append('<div class="grid">')
    for e in ents:
        out.append(tile(e))
    out.append('</div></section>')

out.append('</main>')
out.append('<footer><div class="wrap">Machine-readable list: <code>asset_manifest.csv</code> (path, size, '
           'priority, name, status). Produced from the game data, so ids and names always match '
           '<code>res://data/*.json</code>. Refresh disk status any time: <code>python gen_assets_manifest.py</code></div></footer>')
out.append('<script>%s</script></body></html>' % JS)

open(OUT_HTML, "w", encoding="utf-8").write("\n".join(out))

print("wrote ASSET_MANIFEST.html:", total, "assets |", ndone, "on disk (", round(pct, 1), "% ) |",
      rem["P0"], "P0 /", rem["P1"], "P1 /", rem["P2"], "P2 remaining")
print("preview base:", PREVIEW_BASE)
