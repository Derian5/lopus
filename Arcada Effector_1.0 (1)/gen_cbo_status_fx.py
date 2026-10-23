"""Author CBO burning/blood library documents for Arcaidia Effector.

Uses the editor's Flame Pro design as a reference; never rewrites that reference
or the existing CBO generator. Export these documents with AFX.Atlas.build.
"""
import copy
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent
LIBRARY = ROOT / "library"


def curve(*pairs):
    return {"pts": [{"t": t, "v": v} for t, v in pairs]}


def gradient(*pairs):
    return {"stops": [{"t": t, "c": rgb} for t, rgb in pairs]}


def track(*pairs, mode="ease"):
    return {"keys": [{"t": t, "v": v, "i": {"m": "lin" if mode == "hold" else mode}, "o": {"m": mode}} for t, v in pairs]}


def stream(slug, name, em, pt, *, blend="normal", start=0, end=4.5, opacity=1):
    em = {"bursts": [], "rate": 0, "seed": 1, **em}
    return {"id": "lr_" + slug, "name": name, "type": "emitter", "blend": blend,
            "start": start, "end": end, "opacity": opacity, "em": em, "pt": pt}


def sprite(slug, name, shape, size, color, opacity, scale, **props):
    return {"id": "lr_" + slug, "name": name, "type": "sprite", "blend": "normal", "start": 0,
            "opacity": opacity, "sp": {"sprite": {"kind": "shape", "id": shape, "p": {}},
            "size": size, "color": color, "scale": scale, **props}}


def document(slug, name, w, h, duration, frames, cell_w, cell_h, layers, *, t0=0, t1=-1, cols=4, camera=0):
    return {"app": "arcadia-effects", "v": 2, "doc": {
        "v": 2, "id": "fx_cbo_" + slug, "name": name,
        "comp": {"w": w, "h": h, "dur": duration, "fps": 60}, "cam": {"comp": camera},
        "exp": {"cols": cols, "rows": (frames + cols - 1) // cols, "frames": frames,
                "cellW": cell_w, "cellH": cell_h, "t0": t0, "t1": t1, "mode": "rgba", "ss": 2},
        "layers": layers}, "tex": {}}


def burning():
    reference = json.loads((LIBRARY / "Flame Pro.json").read_text(encoding="utf-8"))["doc"]
    print("Flame reference: " + ", ".join(layer["name"] for layer in reference["layers"]))
    reference_body = next(layer for layer in reference["layers"] if layer["type"] == "emitter" and layer["name"].lower() in ("body", "tongues"))
    flow = {key: copy.deepcopy(reference_body["pt"][key]) for key in
            ("turbMode", "turbScale", "turbOct", "turbRise", "turbWind", "turbRamp") if key in reference_body["pt"]}
    flow.update(turbMode="curl", turbScale=46, turbOct=2, turbRise=100, turbWind=90, turbRamp=0.85,
                drag=1.7, gravY=-24, turbAmp=80, turbSeed=31, spin=10, spinRnd=0.7, rotRnd=1)
    guide = {"on": True, "mode": "guide", "nodes": [{"x": 0, "y": 0}, {"x": 0, "y": -260}],
             "smooth": False, "aim": "none", "attract": 2.6, "flow": 90, "lock": 0}
    pulses = [(index * 0.125, 120 if index % 2 == 0 else 54) for index in range(37)]
    fire = gradient((0, [255, 218, 100]), (0.22, [255, 151, 35]), (0.55, [225, 65, 12]), (1, [99, 22, 10]))
    body = stream("burn_body", "Curling Flame Mass", {
        "x": 0, "y": 130, "shape": "box", "sx": 112, "sy": 54, "dir": "dir", "angle": -90,
        "spread": 22, "speed": 148, "speedRnd": 0.4, "rate": track(*pulses, mode="hold"), "seed": 41, "path": guide}, {
        **flow, "life": 1.05, "lifeRnd": 0.35, "sprite": {"kind": "shape", "id": "smoke", "p": {}},
        "size": 104, "sizeRnd": 0.4, "grad": fire, "glow": 0,
        "sizeOL": curve((0, 0.42), (0.25, 1), (0.66, 0.65), (1, 0.08)),
        "opacityOL": curve((0, 0), (0.12, 0.025), (0.32, 0.075), (0.68, 0.055), (1, 0))}, blend="add")
    core = stream("burn_core", "Low Amber Core", {
        "x": 0, "y": 142, "shape": "box", "sx": 52, "sy": 18, "dir": "dir", "angle": -90,
        "spread": 16, "speed": 125, "speedRnd": 0.35, "rate": 72, "seed": 67, "path": guide}, {
        **flow, "life": 0.44, "lifeRnd": 0.3, "sprite": {"kind": "shape", "id": "smoke", "p": {}},
        "size": 64, "sizeRnd": 0.35, "glow": 0.1,
        "grad": gradient((0, [255, 230, 145]), (0.4, [255, 181, 55]), (1, [240, 89, 15])),
        "sizeOL": curve((0, 0.35), (0.3, 0.8), (1, 0.08)),
        "opacityOL": curve((0, 0), (0.2, 0.07), (0.6, 0.055), (1, 0))}, blend="add")
    tips = stream("burn_tips", "Detached Flame Ribbons", {
        "x": 0, "y": 23, "shape": "box", "sx": 70, "sy": 50, "dir": "dir", "angle": -90,
        "spread": 27, "speed": 110, "speedRnd": 0.4, "rate": 48, "seed": 103, "path": guide}, {
        **flow, "turbSeed": 91, "life": 0.55, "lifeRnd": 0.45,
        "sprite": {"kind": "shape", "id": "smoke", "p": {}}, "size": 70, "sizeRnd": 0.5,
        "grad": fire, "glow": 0, "sizeOL": curve((0, 0.4), (0.25, 0.8), (1, 0.04)),
        "opacityOL": curve((0, 0), (0.25, 0.075), (0.6, 0.055), (1, 0))}, blend="add")
    smoke = stream("burn_smoke", "Charcoal Smoke Behind Fire", {
        "x": 0, "y": 108, "shape": "box", "sx": 82, "sy": 60, "dir": "dir", "angle": -90,
        "spread": 28, "speed": 78, "speedRnd": 0.4, "rate": 26, "seed": 139}, {
        **flow, "turbScale": 70, "turbWind": 65, "life": 1.65, "lifeRnd": 0.3,
        "sprite": {"kind": "shape", "id": "smoke", "p": {}}, "size": 115, "sizeRnd": 0.45,
        "grad": gradient((0, [43, 29, 25]), (0.5, [49, 45, 44]), (1, [76, 72, 68])),
        "sizeOL": curve((0, 0.35), (0.6, 1.1), (1, 1.4)),
        "opacityOL": curve((0, 0), (0.22, 0.08), (0.65, 0.065), (1, 0)), "glow": 0})
    distortion = {"id": "lr_burn_distortion", "name": "Rising Torn Flame Contours", "type": "postfx", "start": 0,
        "end": 4.5, "opacity": 1, "fx": {"effect": "displace", "field": "swirl", "scale": 28, "amount": 45,
        "aspect": 2.7, "oct": 2, "evo": 1.8, "rise": 145, "ramp": 0.85, "y0": 132, "soft": 70, "seed": 73}}
    sparks = stream("burn_embers", "Sharp Rising Embers", {
        "x": 0, "y": 112, "shape": "box", "sx": 100, "sy": 65, "dir": "dir", "angle": -90,
        "spread": 42, "speed": 138, "speedRnd": 0.5, "rate": 15, "seed": 181}, {
        "life": 1.2, "lifeRnd": 0.4, "sprite": {"kind": "shape", "id": "ember", "p": {}},
        "size": 5, "sizeRnd": 0.55, "grad": fire, "gravY": -26, "drag": 0.6, "turbAmp": 30,
        "sizeOL": curve((0, 0.7), (1, 0.1)), "opacityOL": curve((0, 0), (0.1, 0.7), (0.7, 0.45), (1, 0)),
        "glow": 0.2}, blend="add")
    return document("burning_veil", "CBO Burning Veil", 320, 448, 4.5, 32, 160, 224,
                    [sparks, distortion, tips, core, body, smoke], t0=2.5, t1=3.5, cols=8)


def ignition():
    result = burning()
    doc = result["doc"]
    doc["id"] = "fx_cbo_ignition_burst"
    doc["name"] = "CBO Ignition Burst"
    doc["comp"].update(w=320, h=320, dur=0.6)
    doc["exp"].update(cols=4, rows=4, frames=16, cellW=160, cellH=160, t0=0, t1=0.6)
    for layer in doc["layers"]:
        role = layer["id"].removeprefix("lr_burn_")
        layer["id"] = "lr_ignition_" + role
        if layer["type"] == "postfx":
            layer["end"] = 0.6
            layer["fx"].update(y0=40, amount=36)
            continue
        layer["end"] = 0.02
        layer["em"].update(rate=0, y=-30, seed=layer["em"]["seed"] + 401,
                           bursts=[{"t": 0, "n": {"embers": 16, "tips": 20, "core": 12, "body": 52, "smoke": 14}[role]}])
        layer["pt"].update(life={"embers": 0.5, "tips": 0.3, "core": 0.25, "body": 0.45, "smoke": 0.55}[role])
        if role == "tips":
            layer["em"]["y"] = -65
    return result


def blood_hit():
    red = gradient((0, [196, 27, 21]), (0.35, [154, 15, 17]), (1, [65, 6, 11]))
    strands = stream("blood_strands", "Directional Liquid Strands", {
        "x": -14, "y": -4, "dir": "dir", "angle": -8, "spread": 88, "speed": 370,
        "speedRnd": 0.48, "bursts": [{"t": 0, "n": 7}], "seed": 211}, {
        "life": 0.33, "lifeRnd": 0.25, "render": "trail", "trailCore": 0,
        "sprite": {"kind": "shape", "id": "dot", "p": {}}, "size": 5.5, "sizeRnd": 0.45,
        "sizeOL": curve((0, 1), (0.65, 0.6), (1, 0.05)), "sizeOT": curve((0, 0.05), (0.65, 0.35), (1, 1)),
        "opacityOL": curve((0, 0.92), (0.55, 0.86), (1, 0)), "grad": red,
        "gravY": 330, "drag": 2.5, "turbAmp": 0, "glow": 0}, end=0.01)
    drops = stream("blood_drops", "Heavy Falling Droplets", {
        "x": -8, "y": 0, "dir": "dir", "angle": -12, "spread": 116, "speed": 265,
        "speedRnd": 0.65, "bursts": [{"t": 0, "n": 24}], "seed": 239}, {
        "life": 0.52, "lifeRnd": 0.3, "sprite": {"kind": "shape", "id": "dot", "p": {}},
        "size": 7, "sizeRnd": 0.65, "sizeOL": curve((0, 1), (0.7, 0.65), (1, 0.1)),
        "opacityOL": curve((0, 0.9), (0.55, 0.85), (1, 0)), "grad": red,
        "alignVel": True, "stretch": 1.0, "gravY": 420, "drag": 1.1, "glow": 0}, end=0.01)
    mist = stream("blood_mist", "Fine Blood Mist", {
        "x": -10, "y": -5, "dir": "dir", "angle": -10, "spread": 92, "speed": 135,
        "speedRnd": 0.6, "bursts": [{"t": 0, "n": 10}], "seed": 263}, {
        "life": 0.25, "lifeRnd": 0.25, "sprite": {"kind": "shape", "id": "smoke", "p": {}},
        "size": 27, "sizeRnd": 0.5, "sizeOL": curve((0, 0.3), (0.5, 0.8), (1, 1.1)),
        "opacityOL": curve((0, 0.22), (0.4, 0.17), (1, 0)), "grad": red, "drag": 3.5, "glow": 0}, end=0.01)
    return document("blood_impact", "CBO Blood Impact", 384, 256, 0.6, 16, 192, 128, [drops, strands, mist])


def blood_hit_alternate():
    result = blood_hit()
    doc = result["doc"]
    doc["id"] = "fx_cbo_blood_impact_alternate"
    doc["name"] = "CBO Blood Impact Alternate"
    for layer in doc["layers"]:
        layer["id"] += "_alternate"
        layer["em"]["seed"] += 557
        layer["em"]["spread"] *= 1.08
        layer["em"]["speed"] *= 1.08
    return result


def bleeding():
    red = gradient((0, [181, 20, 24]), (0.5, [133, 10, 16]), (1, [67, 5, 10]))
    drops = stream("bleed_drips", "Continuous Wound Drops", {
        "x": 0, "y": -76, "shape": "box", "sx": 74, "sy": 20, "dir": "dir", "angle": 90,
        "spread": 40, "speed": 28, "speedRnd": 0.65, "rate": 24, "seed": 307}, {
        "life": 0.85, "lifeRnd": 0.3, "sprite": {"kind": "shape", "id": "dot", "p": {}},
        "size": 6, "sizeRnd": 0.65, "sizeOL": curve((0, 0.85), (0.6, 1), (1, 0.3)),
        "opacityOL": curve((0, 0.25), (0.15, 0.9), (0.75, 0.8), (1, 0)), "grad": red,
        "alignVel": True, "stretch": 1.25, "gravY": 265, "drag": 0.15, "glow": 0}, end=3.6)
    wisps = stream("bleed_small", "Small Secondary Drops", {
        "x": 0, "y": -68, "shape": "box", "sx": 86, "sy": 28, "dir": "dir", "angle": 90,
        "spread": 65, "speed": 40, "speedRnd": 0.5, "rate": 12, "seed": 331}, {
        "life": 0.65, "lifeRnd": 0.35, "sprite": {"kind": "shape", "id": "dot", "p": {}},
        "size": 3.5, "sizeRnd": 0.6, "sizeOL": curve((0, 1), (1, 0.1)),
        "opacityOL": curve((0, 0.6), (0.6, 0.65), (1, 0)), "grad": red,
        "gravY": 280, "drag": 0.2, "glow": 0}, end=3.6)
    return document("bleeding_drips", "CBO Bleeding Drips", 256, 320, 3.6, 24, 128, 160,
                    [drops, wisps], t0=1.8, t1=3.0, cols=6)


def blood_ground():
    stain = sprite("blood_stain", "Irregular Ground Stain", "smoke", 76, [91, 8, 13],
                   track((0, 0), (0.08, 0.55), (0.65, 0.5), (1.6, 0)),
                   track((0, 0.2), (0.12, 1.0), (1.6, 1.08)), aspect=2.2, squash=1, rot=13)
    satellites = stream("blood_speckles", "Scattered Ground Speckles", {
        "x": 0, "y": 0, "shape": "circle", "sx": 62, "sy": 20, "dir": "out", "speed": 20,
        "speedRnd": 0.6, "bursts": [{"t": 0, "n": 18}], "seed": 367}, {
        "life": 1.5, "lifeRnd": 0.1, "sprite": {"kind": "shape", "id": "dot", "p": {}},
        "size": 10, "sizeRnd": 0.7, "sizeOL": curve((0, 0.4), (0.08, 1), (1, 1.05)),
        "opacityOL": curve((0, 0.5), (0.6, 0.6), (1, 0)), "grad": gradient((0, [122, 10, 17]), (1, [63, 6, 11])),
        "squash": 1, "drag": 8, "glow": 0}, end=0.01)
    return document("blood_ground", "CBO Blood Ground", 320, 192, 1.6, 12, 160, 96,
                    [satellites, stain], camera=60)


def main():
    effects = [burning(), ignition(), blood_hit(), blood_hit_alternate(), bleeding(), blood_ground()]
    for payload in effects:
        doc = payload["doc"]
        path = LIBRARY / (doc["name"] + ".json")
        if path.exists() and json.loads(path.read_text(encoding="utf-8"))["doc"]["id"] != doc["id"]:
            raise RuntimeError("Refusing to replace a different effect: " + str(path))
        path.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        print("Authored %s: %d layers, %d frames" % (path.name, len(doc["layers"]), doc["exp"]["frames"]))


if __name__ == "__main__":
    main()
