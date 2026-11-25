"""Prints the UDID of an available iPhone simulator (newest iOS, a plain recent model if there is one)."""
import json, subprocess, sys
d = json.loads(subprocess.check_output(["xcrun", "simctl", "list", "devices", "available", "-j"]))["devices"]
c = [(k, x) for k, v in d.items() if "iOS" in k for x in v if x["name"].startswith("iPhone")]
if not c: sys.exit("no iPhone simulator available")
def ver(k): return [int(p) for p in k.split("iOS-")[-1].split("-") if p.isdigit()]
newest = max(ver(k) for k, _ in c)
c = [x for k, x in c if ver(k) == newest]
pick = next((x for want in ("iPhone 17", "iPhone 16", "iPhone 17 Pro", "iPhone 16 Pro") for x in c if x["name"] == want), c[0])
sys.stderr.write(f"simulator: {pick['name']} (iOS {'.'.join(map(str, newest))})\n")
print(pick["udid"])
