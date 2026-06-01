#!/bin/bash
#============================================================
# aaPanel PRO Bypass - Full Patch Script
# Chạy 1 lần sau khi cài mới hoặc upgrade bị ghi đè
# Usage: bash /www/server/panel/script/patch_pro.sh
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
echo " aaPanel PRO Bypass - Full Patch"
echo "=========================================="
echo ""

# --- STEP 1: .is_pro.pl ---
echo "[1/8] Tao file .is_pro.pl ..."
echo "true" > "$PANEL_DIR/data/.is_pro.pl"
chmod 600 "$PANEL_DIR/data/.is_pro.pl"
ok ".is_pro.pl created"

# --- STEP 2: license.pl ---
echo "[2/8] Tao file license.pl ..."
cat > "$PANEL_DIR/data/license.pl" << 'EOF'
{
  "product_id": "100000011",
  "type": "pro",
  "expire": "2099-12-31",
  "status": "active",
  "is_lifetime": true
}
EOF
ok "license.pl created"

# --- STEP 3: Crontab fix_pro.sh ---
echo "[3/8] Setup crontab persistence ..."
cat > "$PANEL_DIR/script/fix_pro.sh" << 'FIXEOF'
#!/bin/bash
echo "true" > /www/server/panel/data/.is_pro.pl
chmod 600 /www/server/panel/data/.is_pro.pl
FIXEOF
chmod +x "$PANEL_DIR/script/fix_pro.sh"
crontab -l 2>/dev/null | grep -v "fix_pro" | { cat; echo "* * * * * /www/server/panel/script/fix_pro.sh >/dev/null 2>&1"; } | crontab -
ok "Crontab fix_pro.sh setup"

# --- STEP 4: Patch config.py ---
echo "[4/8] Patch config.py (is_pro) ..."
CONFIG_PY="$PANEL_DIR/class/config.py"
if grep -q 'def is_pro(self,get):' "$CONFIG_PY"; then
    python3 << 'PYEOF'
import re
f = '/www/server/panel/class/config.py'
with open(f, 'r') as fh:
    c = fh.read()
# Replace is_pro function body
c = re.sub(
    r'def is_pro\(self,get\):.*?(?=\n    def |\nclass |\Z)',
    'def is_pro(self,get):\n        return {"status": True, "msg": "ok", "pro": 1, "ltd": 0}\n\n',
    c, count=1, flags=re.DOTALL
)
with open(f, 'w') as fh:
    fh.write(c)
print("OK")
PYEOF
    ok "config.py patched"
else
    info "config.py already patched or pattern not found"
fi

# --- STEP 5: Patch __init__.py ---
echo "[5/8] Patch __init__.py (check_auth_v2) ..."
INIT_PY="$PANEL_DIR/BTPanel/__init__.py"
if grep -q "os.path.exists('data/.is_pro.pl')" "$INIT_PY"; then
    python3 << 'PYEOF'
f = '/www/server/panel/BTPanel/__init__.py'
with open(f, 'r') as fh:
    c = fh.read()
old = """    if os.path.exists('data/.is_pro.pl'):
        return public.return_message(0, 0, 'true')
    return public.return_message(-1, 0, 'false')"""
new = "    return public.return_message(0, 0, 'true')"
c = c.replace(old, new, 1)
with open(f, 'w') as fh:
    fh.write(c)
print("OK")
PYEOF
    ok "__init__.py patched"
else
    info "__init__.py already patched or pattern not found"
fi

# --- STEP 6: Patch panelAuth.py ---
echo "[6/8] Patch panelAuth.py (send_cloud, send_cloud_pro, get_product_auth) ..."
AUTH_PY="$PANEL_DIR/class/panelAuth.py"
python3 << 'PYEOF'
import re
f = '/www/server/panel/class/panelAuth.py'
with open(f, 'r') as fh:
    c = fh.read()

changed = 0

# Patch send_cloud
if 'def send_cloud(self,cloudURL,params):' in c and 'return {"status": True' not in c.split('def send_cloud(self,cloudURL,params):')[1][:100]:
    c = re.sub(
        r'def send_cloud\(self,cloudURL,params\):.*?(?=\n    def |\nclass |\Z)',
        'def send_cloud(self,cloudURL,params):\n        return {"status": True, "success": True, "res": [], "msg": "ok", "pro": 1}\n\n',
        c, count=1, flags=re.DOTALL
    )
    changed += 1

# Patch send_cloud_pro
if 'def send_cloud_pro(self,module,params):' in c:
    # Check if already patched
    idx = c.find('def send_cloud_pro(self,module,params):')
    snippet = c[idx:idx+200]
    if 'return {"status": True' not in snippet[:100]:
        c = re.sub(
            r'def send_cloud_pro\(self,module,params\):.*?(?=\n    def |\nclass |\Z)',
            'def send_cloud_pro(self,module,params):\n        return {"status": True, "success": True, "res": [], "msg": "ok", "pro": 1}\n\n',
            c, count=1, flags=re.DOTALL
        )
        changed += 1

# Patch get_product_auth
if 'def get_product_auth(self,get):' in c:
    idx = c.find('def get_product_auth(self,get):')
    snippet = c[idx:idx+100]
    if 'return []' not in snippet[:80]:
        c = re.sub(
            r'def get_product_auth\(self,get\):.*?(?=\n    def |\nclass |\Z)',
            'def get_product_auth(self,get):\n        return []\n\n',
            c, count=1, flags=re.DOTALL
        )
        changed += 1

with open(f, 'w') as fh:
    fh.write(c)
print(f"OK:{changed}")
PYEOF
ok "panelAuth.py patched"

# --- STEP 7: Patch soft.js ---
echo "[7/8] Patch soft.js (trail:0) ..."
SOFT_JS="$PANEL_DIR/BTPanel/static/js/soft.js"
if [ -f "$SOFT_JS" ]; then
    sed -i 's/trail:1,/trail:0,/g' "$SOFT_JS"
    ok "soft.js patched"
else
    info "soft.js not found"
fi

# --- STEP 8: Patch Vue.js frontend ---
echo "[8/8] Patch Vue.js frontend (disable popup) ..."

# Find Vue.js files dynamically (hash changes on update)
VITE_DIR="$PANEL_DIR/BTPanel/static/vite/js"

# 8a: Patch the main pay modal opener (function fa)
MAIN_JS=$(ls "$VITE_DIR"/index-CmkLJhc0.js 2>/dev/null | head -1)
if [ -n "$MAIN_JS" ]; then
    python3 -c "
f = '$MAIN_JS'
with open(f, 'r') as fh:
    c = fh.read()
old = 'function fa(e){try{const t=at()'
new = 'function fa(e){return;try{const t=at()'
if old in c and new not in c:
    c = c.replace(old, new, 1)
    with open(f, 'w') as fh:
        fh.write(c)
    print('PATCHED')
else:
    print('SKIP')
"
    ok "Vue.js pay modal function disabled"
else
    fail "Vue.js main file not found"
fi

# 8b: Patch popup conditions in home page
HOME_JS=$(ls "$VITE_DIR"/index-B03PWrJZ.js 2>/dev/null | head -1)
if [ -n "$HOME_JS" ]; then
    # Disable proRecommend banner
    sed -i 's/a(n).show&&!a(l)/!1/g' "$HOME_JS"
    # Disable header auth popup
    sed -i 's/a(f).status&&a(c)!=="Lifetime"/!1/g' "$HOME_JS"
    ok "Vue.js popup conditions disabled"
else
    info "Vue.js home file not found (may have different hash)"
fi

# --- RESTART ---
echo ""
echo "=========================================="
echo " Restarting panel ..."
echo "=========================================="
bt restart 2>/dev/null
sleep 2
bash "$PANEL_DIR/script/fix_pro.sh"

echo ""
echo "=========================================="
echo " HOAN TAT! Patch PRO da ap dung."
echo " Mo trinh duye: Ctrl+Shift+Del (xoa cache)"
echo " Sau do Ctrl+F5 de reload."
echo "=========================================="
echo ""
