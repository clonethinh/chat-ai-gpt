#!/bin/bash
#============================================================
# aaPanel PRO Bypass - Full Patch Script v3
# Chay 1 lan duy nhat sau khi cai moi hoac bt update
# Usage: bash /www/patch_pro.sh
#============================================================

PANEL_DIR="/www/server/panel"
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

ok()   { echo -e "  ${GREEN}[OK]${NC} $1"; }
fail() { echo -e "  ${RED}[FAIL]${NC} $1"; }
info() { echo -e "  ${YELLOW}[INFO]${NC} $1"; }

echo ""
echo "=========================================="
echo " aaPanel PRO Bypass v3 - One-shot Patch"
echo "=========================================="
echo ""

# --- STEP 1: Disable debug mode (prevents file watcher restart loop) ---
echo "[1/7] Disable debug mode (anti file-watcher loop) ..."
rm -f "$PANEL_DIR/data/debug.pl"
ok "debug.pl removed"

# --- STEP 2: .is_pro.pl + license.pl + crontab ---
echo "[2/7] Setup PRO license files + crontab persistence ..."
echo "true" > "$PANEL_DIR/data/.is_pro.pl"
chmod 600 "$PANEL_DIR/data/.is_pro.pl"

cat > "$PANEL_DIR/data/license.pl" << 'EOF'
{
  "product_id": "100000011",
  "type": "pro",
  "expire": "2099-12-31",
  "status": "active",
  "is_lifetime": true
}
EOF

cat > "$PANEL_DIR/script/fix_pro.sh" << 'FIXEOF'
#!/bin/bash
echo "true" > /www/server/panel/data/.is_pro.pl
chmod 600 /www/server/panel/data/.is_pro.pl
FIXEOF
chmod +x "$PANEL_DIR/script/fix_pro.sh"
crontab -l 2>/dev/null | grep -v "fix_pro" | { cat; echo "* * * * * /www/server/panel/script/fix_pro.sh >/dev/null 2>&1"; } | crontab -
ok ".is_pro.pl + license.pl + crontab ready"

# --- STEP 3: Python backend patches ---
echo "[3/7] Patching Python backend ..."
python3 << 'PYPATCH'
import re, os

P = "/www/server/panel"
R = []

def patch_file(relpath, label, patches):
    f = os.path.join(P, relpath)
    if not os.path.exists(f):
        R.append(f"{label}: NOT FOUND"); return
    with open(f, 'r') as fh:
        c = fh.read()
    changed = 0
    for ptype, *args in patches:
        if ptype == 'regex':
            pattern, replacement = args
            if '# [PATCH]' not in c:
                c2 = re.sub(pattern, replacement, c, count=1, flags=re.DOTALL)
                if c2 != c:
                    c = c2; changed += 1
        elif ptype == 'replace':
            old, new = args
            if old in c and '# [PATCH]' not in new.split('\n')[0] and '# [PATCH]' not in c[max(0,c.find(old)-50):c.find(old)+len(old)+50]:
                c = c.replace(old, new, 1); changed += 1
            elif old in c:
                pass  # already patched
        elif ptype == 'replace_safe':
            old, new = args
            if old in c:
                c = c.replace(old, new, 1); changed += 1
    if changed > 0:
        with open(f, 'w') as fh:
            fh.write(c)
    R.append(f"{label}: {changed} patch(es)")

# 1. config.py - is_pro()
f = os.path.join(P, 'class/config.py')
if os.path.exists(f):
    with open(f, 'r') as fh: c = fh.read()
    if 'def is_pro(self,get):' in c and '# [PATCH]' not in c:
        c = re.sub(
            r'def is_pro\(self,get\):.*?(?=\n    def |\nclass |\Z)',
            'def is_pro(self,get):\n        return {"status": True, "msg": "ok", "pro": 1, "ltd": 1}  # [PATCH]\n\n',
            c, count=1, flags=re.DOTALL
        )
        with open(f, 'w') as fh: fh.write(c)
        R.append("config.py: OK")
    else:
        R.append("config.py: SKIP (already patched or not found)")

# 2. config_v2.py - is_pro()
f = os.path.join(P, 'class_v2/config_v2.py')
if os.path.exists(f):
    with open(f, 'r') as fh: c = fh.read()
    if 'def is_pro(self, get):' in c and '# [PATCH]' not in c:
        c = re.sub(
            r'    def is_pro\(self, get\):.*?(?=\n    def |\nclass |\Z)',
            '    def is_pro(self, get):  # [PATCH]\n        return {"status": True, "msg": "ok", "pro": 1, "ltd": 1}\n\n',
            c, count=1, flags=re.DOTALL
        )
        with open(f, 'w') as fh: fh.write(c)
        R.append("config_v2.py: OK")
    else:
        R.append("config_v2.py: SKIP")

# 3. panelAuth.py - send_cloud, send_cloud_pro, get_product_auth
f = os.path.join(P, 'class/panelAuth.py')
if os.path.exists(f):
    with open(f, 'r') as fh: c = fh.read()
    changed = 0
    for func_name, ret_val in [
        ('send_cloud(self,cloudURL,params)', '{"status": True, "success": True, "res": [], "msg": "ok", "pro": 1}'),
        ('send_cloud_pro(self,module,params)', '{"status": True, "success": True, "res": [], "msg": "ok", "pro": 1}'),
        ('get_product_auth(self,get)', '[]'),
    ]:
        search = f'def {func_name}'
        if search in c:
            idx = c.find(search)
            if '# [PATCH]' not in c[idx:idx+300]:
                c = re.sub(
                    rf'    def {re.escape(func_name)}.*?(?=\n    def |\nclass |\Z)',
                    f'    def {func_name}:  # [PATCH]\n        return {ret_val}\n\n',
                    c, count=1, flags=re.DOTALL
                )
                changed += 1
    if changed > 0:
        with open(f, 'w') as fh: fh.write(c)
    R.append(f"panelAuth.py: {changed} patches")

# 4. panel_auth_v2.py - get_product_auth, get_product_auth_all
f = os.path.join(P, 'class_v2/panel_auth_v2.py')
if os.path.exists(f):
    with open(f, 'r') as fh: c = fh.read()
    changed = 0
    for func_sig in ['get_product_auth(self, get)', 'get_product_auth_all(self, get)']:
        search = f'def {func_sig}'
        if search in c:
            idx = c.find(search)
            if '# [PATCH]' not in c[idx:idx+300]:
                c = re.sub(
                    rf'    def {re.escape(func_sig)}.*?(?=\n    def |\nclass |\Z)',
                    f'    def {func_sig}:  # [PATCH]\n        return public.return_message(0, 0, [])\n\n',
                    c, count=1, flags=re.DOTALL
                )
                changed += 1
    if changed > 0:
        with open(f, 'w') as fh: fh.write(c)
    R.append(f"panel_auth_v2.py: {changed} patches")

# 5. panel_plugin_v2.py - force PRO in get_cloud_list + check_accept bypass
f = os.path.join(P, 'class_v2/panel_plugin_v2.py')
if os.path.exists(f):
    with open(f, 'r') as fh: c = fh.read()
    changed = 0

    # 5a. Force PRO in get_cloud_list
    old5a = "        softList = public.load_soft_list(True if force == 1 else False)\n\n        if get and 'init' in get:"
    new5a = """        softList = public.load_soft_list(True if force == 1 else False)

        # [PATCH] Force PRO license - all plugins activated
        try:
            softList['pro'] = 0  # permanent pro
            softList['ltd'] = 1  # enterprise active
            if 'list' in softList:
                for p in softList['list']:
                    p['endtime'] = 0  # permanent
                    p['state'] = 1
        except:
            pass

        if get and 'init' in get:"""
    if old5a in c and '# [PATCH] Force PRO license' not in c:
        c = c.replace(old5a, new5a, 1); changed += 1

    # 5b. check_accept bypass
    old5b = """    #检查权限
    def check_accept(self,get):
        args = public.dict_obj()
        args.type = '8'
        p_list = self.get_cloud_list(args)
        for p in p_list['list']:
            if p['name'] == get.name:
                if int(p_list['pro']) < 0 and int(p['endtime']) < 0: return False
                break

        args.type = '10'
        p_list = self.get_cloud_list(args)
        for p in p_list['list']:
            if p['name'] == get.name:
                if not 'endtime' in p: continue
                if int(p['endtime']) < 0: return False
                break

        args.type = '12'
        p_list = self.get_cloud_list(args)
        for p in p_list['list']:
            if not p['type'] in [12,'12']: continue
            if p['name'] == get.name:
                if not 'endtime' in p: continue
                if int(p_list['ltd']) < 1 and int(p['endtime']) < 1: return False
                break
        return True"""
    new5b = """    #检查权限
    def check_accept(self,get):
        return True  # [PATCH] All plugins accepted"""
    if old5b in c:
        c = c.replace(old5b, new5b, 1); changed += 1

    if changed > 0:
        with open(f, 'w') as fh: fh.write(c)
    R.append(f"panel_plugin_v2.py: {changed} patches")

# 6. PluginLoader.py - bypass NoAuthorizationException (safe: just pass, no fake module)
f = os.path.join(P, 'class/public/PluginLoader.py')
if os.path.exists(f):
    with open(f, 'r') as fh: c = fh.read()
    old6 = "raise NoAuthorizationException(module_obj['msg'])"
    new6 = "pass  # [PATCH] Bypass NoAuthorizationException"
    if old6 in c and '# [PATCH]' not in c:
        c = c.replace(old6, new6, 1)
        with open(f, 'w') as fh: fh.write(c)
        R.append("PluginLoader.py: OK (pass bypass)")
    else:
        R.append("PluginLoader.py: SKIP")

# 7. check_auth.py - always write .is_pro.pl
f = os.path.join(P, 'script/check_auth.py')
if os.path.exists(f):
    with open(f, 'r') as fh: c = fh.read()
    old7 = """if int(plugin_list["pro"]) > time.time() or __IS_PRO_MEMBER:
    public.writeFile('data/.is_pro.pl','True')
else:
    if os.path.exists('data/.is_pro.pl'): os.remove('data/.is_pro.pl')"""
    new7 = """# [PATCH] Always PRO
public.writeFile('data/.is_pro.pl','True')"""
    if old7 in c and '# [PATCH]' not in c:
        c = c.replace(old7, new7, 1)
        with open(f, 'w') as fh: fh.write(c)
        R.append("check_auth.py: OK")
    else:
        R.append("check_auth.py: SKIP")

for r in R:
    print(f"  {r}")
PYPATCH
ok "Python backend done"

# --- STEP 4: JavaScript frontend patches ---
echo ""
echo "[4/7] Patching JavaScript frontend ..."

VITE_DIR="$PANEL_DIR/BTPanel/static/vite/js"

python3 << 'JSPATCH'
import os, glob, re

VITE_DIR = "/www/server/panel/BTPanel/static/vite/js"
R = []

def js_patch(filepath, label, patches):
    if not os.path.exists(filepath):
        R.append(f"{label}: NOT FOUND"); return
    with open(filepath, 'r') as f:
        c = f.read()
    changed = 0
    for old, new in patches:
        if old in c and new not in c:
            c = c.replace(old, new, 1)
            changed += 1
    if changed > 0:
        with open(filepath, 'w') as f:
            f.write(c)
    R.append(f"{label}: {changed} patch(es)")

# 1. soft-D4s0uPts.js
js_patch(os.path.join(VITE_DIR, "soft-D4s0uPts.js"), "soft-D4s0uPts.js", [
    ('u().isFree?(f({source:e}),Promise.reject()):await v(a,s)',
     'await v(a,s)  /*[PATCH]*/'),
    ('if(!(s||y.isLtd)){f({source:e});return}',
     'if(!1)/*[PATCH]*/'),
])

# 2. soft-legacy-*.js
for lf in glob.glob(os.path.join(VITE_DIR, "soft-legacy-*.js")):
    js_patch(lf, os.path.basename(lf), [
        ('t().isFree?(a({source:s}),Promise.reject()):await(async',
         'await(async  /*[PATCH]*/'),
        ('n||c.isLtd?i?await p(r):l(r.name,o):a({source:s})',
         'i?await p(r):l(r.name,o)  /*[PATCH]*/'),
    ])

# 3. Main index JS (auto-detect from HTML)
html_file = "/www/server/panel/BTPanel/templates/default/index_new.html"
main_js_name = None
if os.path.exists(html_file):
    with open(html_file, 'r') as f:
        html = f.read()
    m = re.search(r'index-([A-Za-z0-9_-]+)\.js', html)
    if m:
        main_js_name = f"index-{m.group(1)}.js"

patched_main = set()
for js_name in filter(None, [main_js_name, "index-CmkLJhc0.js"]):
    js_path = os.path.join(VITE_DIR, js_name)
    if js_path in patched_main or not os.path.exists(js_path):
        continue
    patched_main.add(js_path)
    js_patch(js_path, js_name, [
        ('function fa(e){try{const t=at()',
         'function fa(e){return;try{const t=at()'),
        ('if(at().isFree){fa(e),s(!1);return}t(!0)',
         't(!0)  /*[PATCH]*/'),
        ('if(t.isFree){fa({source:371});return}',
         'if(!1)/*[PATCH]*/'),
    ])

# 4. Home page JS (index-B03PWrJZ.js or auto-detect via isBuy)
home_js = os.path.join(VITE_DIR, "index-B03PWrJZ.js")
if not os.path.exists(home_js):
    # Try to find file containing isBuy
    for f in glob.glob(os.path.join(VITE_DIR, "index-*.js")):
        if 'legacy' in f: continue
        try:
            with open(f, 'r') as fh:
                if 'o.isBuy?(w()' in fh.read():
                    home_js = f; break
        except: pass
js_patch(home_js, os.path.basename(home_js), [
    ('o.isBuy?(w(),T(a(G),{key:1,class:\\"install\\"',
     '!0?(w(),T(a(G),{key:1,class:\\"install\\"  /*[PATCH]*/'),
    ('if(u.isFree){E({source:350});return}',
     'if(!1)/*[PATCH]*/'),
    ('!(f.isFree&&f.aaPanelPro)&&n.value&&n.value.installed===!1',
     'n.value&&n.value.installed===!1  /*[PATCH]*/'),
])

for r in R:
    print(f"  {r}")
JSPATCH

# Patch soft.js trail
SOFT_JS="$PANEL_DIR/BTPanel/static/js/soft.js"
if [ -f "$SOFT_JS" ]; then
    sed -i 's/trail:1,/trail:0,/g' "$SOFT_JS"
    ok "soft.js trail patched"
fi

ok "JavaScript frontend done"

# --- STEP 5: Clear caches ---
echo ""
echo "[5/7] Clearing caches ..."
find "$PANEL_DIR" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null
find "$PANEL_DIR" -name "*.pyc" -delete 2>/dev/null
rm -f "$PANEL_DIR/data/plugin_bin.pl" 2>/dev/null
rm -f /tmp/bmac_* 2>/dev/null
ok "Caches cleared"

# --- STEP 6: Verify patches ---
echo ""
echo "[6/7] Verifying patches ..."
TOTAL=0
for f in class/config.py class_v2/config_v2.py class/panelAuth.py class_v2/panel_auth_v2.py class_v2/panel_plugin_v2.py class/public/PluginLoader.py script/check_auth.py; do
    count=$(grep -c "# \[PATCH\]" "$PANEL_DIR/$f" 2>/dev/null || echo 0)
    TOTAL=$((TOTAL + count))
    if [ "$count" -gt 0 ]; then
        ok "$f: $count patch(es)"
    else
        fail "$f: NO patches!"
    fi
done
echo "  Total Python patches: $TOTAL"

# --- STEP 7: Restart ---
echo ""
echo "[7/7] Restarting panel ..."
bt stop 2>/dev/null
sleep 2
bash "$PANEL_DIR/script/fix_pro.sh"
bt start 2>/dev/null
sleep 3
ok "Panel restarted"

echo ""
echo "=========================================="
echo " PRO Bypass v3 - Complete!"
echo "=========================================="
echo " - PRO vinh vien (permanent)"
echo " - Tat ca plugin PRO: Cai dat duoc"
echo " - Chay lai: bash /www/patch_pro.sh"
echo "=========================================="
echo ""
