import json,sys,glob,os
sys.stdout.reconfigure(encoding="utf-8",errors="replace")
for p in sorted(glob.glob("godot_project/data/ships/*.json")):
    d=json.load(open(p,encoding="utf-8"))
    nm=str(d.get("name",""))
    if any(k in nm for k in ["漩涡","旋涡","巨鸟"]):
        print(os.path.basename(p), d.get("id"), nm, d.get("name_en"), d.get("ship_group"), "model_key=",d.get("model_key"), "sof_hull=",d.get("sof_hull"), "type_id=",d.get("type_id"))
