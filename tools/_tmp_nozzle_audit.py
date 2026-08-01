import json,sys,glob,os
import numpy as np
sys.stdout.reconfigure(encoding="utf-8",errors="replace")
ships={}
for p in glob.glob("godot_project/data/ships/*.json"):
    d=json.load(open(p,encoding="utf-8"))
    mk=d.get("model_key")
    if mk: ships[mk]=d
rows=[]
for p in sorted(glob.glob("godot_project/assets/models/ships/*/engine_boosters.json")):
    key=os.path.basename(os.path.dirname(p))
    d=json.load(open(p,encoding="utf-8"))
    ab=d.get("hull_aabb") or {}
    if not ab: continue
    pos=np.array([it["pos"] for it in d.get("items",[])],float)
    if len(pos)==0: continue
    o=np.array(ab["position"],float); s=np.array(ab["size"],float)
    n=(pos-o)/s
    sh=ships.get(key,{})
    rows.append(dict(key=key, name=sh.get("name","?"), grp=sh.get("ship_group","?"),
        hull=d.get("sof_hull"), src=ab.get("source"), n=len(pos),
        zmin=n[:,2].min(), zmax=n[:,2].max(), xdev=float(np.abs(n[:,0]-0.5).max()),
        ydev=float(np.abs(n[:,1]-0.5).max()),
        oob=int(((n<-0.05)|(n>1.05)).any(axis=1).sum())))
print(f"packs with sidecar: {len(rows)}\n")
def flag(r):
    f=[]
    if r["src"]!="shapeEllipsoid": f.append("aabb="+str(r["src"]))
    if r["oob"]: f.append(f"oob={r['oob']}")
    if r["zmin"]>0.45: f.append(f"not-aft z>={r['zmin']:.2f}")
    if r["xdev"]>0.45 or r["ydev"]>0.45: f.append(f"offcentre x{r['xdev']:.2f} y{r['ydev']:.2f}")
    return f
bad=[r for r in rows if flag(r)]
print(f"--- flagged {len(bad)} ---")
for r in sorted(bad,key=lambda r:-len(flag(r))):
    print(f"{r['key']:26} {r['name']:12} {r['grp']:14} {r['hull']:10} n={r['n']:3}  z[{r['zmin']:.2f},{r['zmax']:.2f}] | {', '.join(flag(r))}")
print("\n--- the two reported ---")
for r in rows:
    if r["key"] in ("mmte_siwangxuanwo","jdl_juniao"):
        print(f"{r['key']:26} {r['name']:12} {r['grp']:14} hull={r['hull']} n={r['n']} src={r['src']} z[{r['zmin']:.2f},{r['zmax']:.2f}] xdev={r['xdev']:.2f} ydev={r['ydev']:.2f} oob={r['oob']}")
