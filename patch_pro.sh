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

# --- STEP 5: PluginLoader.py (replace .so with .py) ---
echo ""
echo "[5/10] Replacing PluginLoader.so with PluginLoader.py ..."

# Backup and remove .so files
mkdir -p /tmp/pluginloader_backup
cp "$PANEL_DIR/class/PluginLoader.so" /tmp/pluginloader_backup/ 2>/dev/null || true
rm -f "$PANEL_DIR/class/PluginLoader"*.so

# Create class/PluginLoader.py (simple implementation, no circular import)
cat > "$PANEL_DIR/class/PluginLoader.py" << 'PLUGINLOADEREOF'
import os
import sys
import json

def get_module(filename):
    """
    Get module by filename - simplified implementation
    """
    if not filename or not os.path.exists(filename):
        return {'status': False, 'msg': f'File not found: {filename}'}
    
    # Check cache
    if filename in sys.modules:
        return sys.modules[filename]
    
    # Read file
    with open(filename, 'r', encoding='utf-8') as f:
        code = f.read()
    
    # Check if encrypted
    if 'import' not in code:
        try:
            lines = code.split('\n')
            decrypted = ''
            for line in lines:
                line = line.strip()
                if not line:
                    continue
                decrypted += _decrypt_line(line)
            code = decrypted
        except Exception as e:
            return {'status': False, 'msg': f'Failed to decode: {e}'}
    
    # Compile and execute
    import types
    code_obj = compile(code, filename, 'exec')
    module = sys.modules.setdefault(filename, types.ModuleType(filename))
    module.__file__ = filename
    module.__package__ = ''
    exec(code_obj, module.__dict__)
    
    return module

def _decrypt_line(data):
    """Decrypt a single encrypted line"""
    from Crypto.Cipher import AES
    import base64
    key = 'Z2B87NEAS2BkxTrh'
    iv = 'WwadH66EGWpeeTT6'
    encodebytes = base64.decodebytes(data.encode('utf-8'))
    aes = AES.new(key.encode('utf-8'), AES.MODE_CBC, iv.encode('utf-8'))
    de_text = aes.decrypt(encodebytes)
    unpad = lambda s: s[0:-s[-1]]
    de_text = unpad(de_text)
    return de_text.decode('utf-8')

def get_plugin_list(force=False):
    """Get plugin list"""
    import public
    api_url = public.OfficialApiBase() + '/api/panel/getSoftListEn'
    data_path = os.path.join(public.get_panel_path(), 'data')
    
    if not os.path.exists(data_path):
        os.makedirs(data_path, 384)
    
    plugin_list = {}
    plugin_list_file = os.path.join(data_path, 'plugin_list.json')
    
    if os.path.exists(plugin_list_file) and not force:
        plugin_list_body = public.readFile(plugin_list_file)
        try:
            plugin_list = json.loads(plugin_list_body)
        except:
            plugin_list = {}
    
    if not os.path.exists(plugin_list_file) or force or not plugin_list:
        try:
            res = public.HttpPost(api_url, {'type': '0'})
        except Exception as ex:
            raise public.error_conn_cloud(str(ex))
        if not res:
            raise Exception(False, 'failed to get soft list')
        plugin_list = json.loads(res)
        if type(plugin_list) != dict or 'list' not in plugin_list:
            raise Exception('failed to parse soft list')
        public.writeFile(plugin_list_file, json.dumps(plugin_list))
    
    return plugin_list

def get_auth_state():
    """Get auth state - always enterprise"""
    return 2  # [PATCH] Always enterprise

def parse_plugin_list(force=False):
    """Parse plugin list - always success"""
    return True  # [PATCH] Always success

def plugin_run(plugin_name, def_name, args):
    """Execute plugin method"""
    import public
    
    if not plugin_name or not def_name:
        return public.returnMsg(False, 'parameter incorrect: module_name and def_name cannot be empty.')
    
    plugin_path = public.get_plugin_path(plugin_name)
    is_php = os.path.exists(os.path.join(plugin_path, 'index.php'))
    
    if is_php:
        plugin_file = os.path.join(plugin_path, 'index.php')
    else:
        plugin_file = os.path.join(plugin_path, plugin_name + '_main.py')
    
    if not os.path.exists(plugin_file):
        return public.returnMsg(False, 'plugin not found')
    
    if not is_php:
        _name = "{}_main".format(plugin_name)
        # [PATCH] Add plugin path to sys.path so __import__ can find the module
        if plugin_path not in sys.path:
            sys.path.insert(0, plugin_path)
        plugin_main = __import__(_name)
        
        if not hasattr(plugin_main, _name):
            return public.returnMsg(False, 'plugin class name is invalid')
        
        try:
            if sys.version_info[0] == 2:
                reload(plugin_main)
            else:
                from imp import reload
                reload(plugin_main)
        except:
            pass
        
        plugin_obj = getattr(plugin_main, _name)()
        
        if not hasattr(plugin_obj, def_name):
            return public.returnMsg(False, 'not find method [%s] in plugin [%s]' % (def_name, plugin_name))
        
        if args is not None and 'plugin_get_object' in args and args.plugin_get_object == 1:
            return getattr(plugin_obj, def_name)
        
        return getattr(plugin_obj, def_name)(args)
    else:
        if args is not None and 'plugin_get_object' in args and args.plugin_get_object == 1:
            return None
        import panelPHP
        args.s = def_name
        args.name = plugin_name
        return panelPHP.panelPHP(plugin_name).exec_php_script(args)

def module_run(module_name, def_name, args):
    """Execute module method"""
    import public
    
    if not module_name or not def_name:
        return public.returnMsg(False, 'parameter incorrect: module_name and def_name cannot be empty.')
    
    model_index = args.get('model_index', None)
    class_path = public.get_class_path()
    panel_path = public.get_panel_path()
    
    module_file = None
    if 'model_index' in args:
        if model_index in ['mod']:
            module_file = os.path.join(panel_path, 'mod', 'project', module_name + 'Mod.py')
        elif model_index:
            module_file = os.path.join(class_path, model_index + "Model", module_name + 'Model.py')
        else:
            module_file = os.path.join(class_path, "projectModel", module_name + 'Model.py')
    else:
        module_list = get_module_list()
        for name in module_list:
            module_file = os.path.join(class_path, name, module_name + 'Model.py')
            if os.path.exists(module_file):
                break
    
    if not os.path.exists(module_file):
        return public.returnMsg(False, 'module file [%s] not exist' % module_name)
    
    if not public.path_safe_check(module_file):
        return public.returnMsg(False, 'parameter incorrect')
    
    def_object = public.get_script_object(module_file)
    if not def_object:
        return public.returnMsg(False, 'module [%s] not found' % module_name)
    
    try:
        run_object = getattr(def_object.main(), def_name, None)
    except:
        return public.returnMsg(False, 'module [%s] failed to instance class' % module_name)
    
    if not run_object:
        return public.returnMsg(False, 'not found method [%s] in module [%s]' % (def_name, module_name))
    
    if 'module_get_object' in args and args.module_get_object == 1:
        return run_object
    
    return run_object(args)

def get_module_list():
    """Get module list"""
    import public
    module_list = []
    class_path = public.get_class_path()
    if not os.path.exists(class_path):
        return module_list
    for name in os.listdir(class_path):
        path = os.path.join(class_path, name)
        if not name or name.endswith('.py') or name[0] == '.' or not name.endswith('Model') or os.path.isfile(path):
            continue
        module_list.append(name)
    return module_list

def db_encrypt(data):
    """Database encrypt"""
    try:
        key = __get_db_sgin()
        iv = __get_db_iv()
        str_arr = data.split('\n')
        res_str = ''
        for d in str_arr:
            if not d:
                continue
            res_str += __aes_encrypt(d, key, iv)
    except:
        res_str = data
    return {'status': True, 'msg': res_str}

def db_decrypt(data):
    """Database decrypt"""
    try:
        key = __get_db_sgin()
        iv = __get_db_iv()
        str_arr = data.split('\n')
        res_str = ''
        for d in str_arr:
            if not d:
                continue
            res_str += __aes_decrypt(d, key, iv)
    except:
        res_str = data
    return {'status': True, 'msg': res_str}

def __get_db_sgin():
    keystr = '3gP7+k_7lSNg3$+Fj!PKW+6$KYgHtw#R'
    key = ''
    for i in range(31):
        if i & 1 == 0:
            key += keystr[i]
    return key

def __get_db_iv():
    import public
    panel_path = public.get_panel_path()
    div_file = os.path.join(panel_path, 'data', 'div.pl')
    if not os.path.exists(div_file):
        s = public.GetRandomString(16)
        s = __aes_encrypt_module(s)
        div = public.get_div(s)
        public.WriteFile(div_file, div)
    if os.path.exists(div_file):
        div = public.ReadFile(div_file)
        div = __aes_decrypt_module(div)
    else:
        keystr = '4jHCpBOFzL4*piTn^-4IHBhj-OL!fGlB'
        div = ''
        for i in range(31):
            if i & 1 == 0:
                div += keystr[i]
    return div

def __aes_encrypt_module(data):
    key = 'Z2B87NEAS2BkxTrh'
    iv = 'WwadH66EGWpeeTT6'
    return __aes_encrypt(data, key, iv)

def __aes_decrypt_module(data):
    key = 'Z2B87NEAS2BkxTrh'
    iv = 'WwadH66EGWpeeTT6'
    return _decrypt_line(data)

def __aes_encrypt(data, key, iv):
    from Crypto.Cipher import AES
    import base64
    data = (lambda s: s + (16 - len(s) % 16) * chr(16 - len(s) % 16).encode('utf-8'))(data.encode('utf-8'))
    aes = AES.new(key.encode('utf8'), AES.MODE_CBC, iv.encode('utf8'))
    encryptedbytes = aes.encrypt(data)
    en_text = base64.b64encode(encryptedbytes)
    return en_text.decode('utf-8')
PLUGINLOADEREOF

# Create class/public/PluginLoader.py (no circular import)
cat > "$PANEL_DIR/class/public/PluginLoader.py" << 'PUBLICLOADEREOF'
from .exceptions import NoAuthorizationException, HintException

# [PATCH] Simple implementation - no imports to avoid circular dependency
def get_module(filename: str):
    """
    Simplified get_module - bypass authorization checks
    Returns None to let caller handle, or raises ImportError
    """
    import sys
    import os
    
    # Read and compile the file directly
    if not filename or not os.path.exists(filename):
        raise ImportError(filename)
    
    # Check if already loaded
    cached = sys.modules.get(filename, None)
    if cached:
        return cached
    
    # Read source code
    with open(filename, 'r', encoding='utf-8') as f:
        code = f.read()
    
    # If code doesn't have imports, it might be encrypted
    if code.find('import') == -1:
        # Try to decrypt
        try:
            lines = code.split('\n')
            decrypted = ''
            for line in lines:
                line = line.strip()
                if not line:
                    continue
                decrypted += _decrypt_line(line)
            code = decrypted
        except:
            raise ImportError(f'Failed to decode: {filename}')
    
    if not code or code.find('import') == -1:
        raise ImportError(f'Invalid module: {filename}')
    
    # Compile and execute
    from types import ModuleType
    code_obj = compile(code, filename, 'exec')
    module = sys.modules.setdefault(filename, ModuleType(filename))
    module.__file__ = filename
    module.__package__ = ''
    exec(code_obj, module.__dict__)
    
    return module

def _decrypt_line(data):
    """Decrypt a single line (for encrypted modules)"""
    from Crypto.Cipher import AES
    import base64
    key = 'Z2B87NEAS2BkxTrh'
    iv = 'WwadH66EGWpeeTT6'
    encodebytes = base64.decodebytes(data.encode('utf-8'))
    aes = AES.new(key.encode('utf-8'), AES.MODE_CBC, iv.encode('utf-8'))
    de_text = aes.decrypt(encodebytes)
    unpad = lambda s: s[0:-s[-1]]
    de_text = unpad(de_text)
    return de_text.decode('utf-8')
PUBLICLOADEREOF

ok "PluginLoader.py installed"

# --- STEP 6: Revert OfficialApiBase() to www.aapanel.com ---
echo ""
echo "[6/10] Ensuring OfficialApiBase() uses www.aapanel.com ..."

python3 << 'APIURLPATCH'
import os
f = "/www/server/panel/class/public/common.py"
if os.path.exists(f):
    with open(f, 'r') as fh:
        c = fh.read()
    
    # Revert OfficialApiBase() to www.aapanel.com (NOT aa.maxcdn.top)
    old1 = """# 官网API根地址
def OfficialApiBase():
    return 'https://aa.maxcdn.top'"""
    new1 = """# 官网API根地址
def OfficialApiBase():
    return 'https://www.aapanel.com'"""
    
    if old1 in c:
        c = c.replace(old1, new1, 1)
        print("  common.py: OfficialApiBase() reverted to www.aapanel.com")
    else:
        print("  common.py: OfficialApiBase() already correct")
    
    # Keep sync_plugin_OfficialApiBase() as aa.maxcdn.top (for downloads)
    old2 = """# 部分插件下载地址
def sync_plugin_OfficialApiBase():
    return 'https://download.aapanel.com'"""
    new2 = """# 部分插件下载地址
def sync_plugin_OfficialApiBase():
    return 'https://aa.maxcdn.top'"""
    
    if old2 in c:
        c = c.replace(old2, new2, 1)
        print("  common.py: sync_plugin_OfficialApiBase() patched to aa.maxcdn.top")
    else:
        print("  common.py: sync_plugin_OfficialApiBase() already patched")
    
    with open(f, 'w') as fh:
        fh.write(c)
APIURLPATCH

ok "API URLs configured"

# --- STEP 7: Mirror download URL ---
echo ""
echo "[7/10] Patching __download_plugin to use mirror ..."

python3 << 'MIRRORPATCH'
import os
f = "/www/server/panel/class_v2/panel_plugin_v2.py"
if os.path.exists(f):
    with open(f, 'r') as fh:
        c = fh.read()
    
    # Add mirror URL variable
    old1 = """        if not os.path.exists(self.__tmp_path):
            os.makedirs(self.__tmp_path, 384)

        if not cache.get(pkey):"""
    new1 = """        if not os.path.exists(self.__tmp_path):
            os.makedirs(self.__tmp_path, 384)

        # [PATCH] Use mirror for PRO plugin downloads
        mirror_download_url = 'https://aa.maxcdn.top/api/panel/download_plugin'

        if not cache.get(pkey):"""
    
    if old1 in c and 'mirror_download_url' not in c:
        c = c.replace(old1, new1, 1)
        
        # Replace download URL
        old2 = """            try:
                cache.set(pkey, '0/0/0', 3600)
                download_res = requests.post(
                    self.__download_sync_plugin,
                    pdata,"""
        new2 = """            try:
                cache.set(pkey, '0/0/0', 3600)
                download_res = requests.post(
                    mirror_download_url,
                    pdata,"""
        
        if old2 in c:
            c = c.replace(old2, new2, 1)
            with open(f, 'w') as fh:
                fh.write(c)
            print("  panel_plugin_v2.py: mirror download patched")
        else:
            print("  panel_plugin_v2.py: SKIP (download pattern not found)")
    elif 'mirror_download_url' in c:
        print("  panel_plugin_v2.py: already patched")
    else:
        print("  panel_plugin_v2.py: SKIP (pattern not found)")
MIRRORPATCH

ok "Mirror download URL patched"

# --- STEP 8: Create plugin_list.json ---
echo ""
echo "[8/10] Creating plugin_list.json from mirror API ..."

python3 << 'PLUGINLISTPATCH'
import json, requests

try:
    # Fetch from mirror
    resp = requests.post(
        'https://aa.maxcdn.top/api/panel/getSoftListEn',
        data={'type': '0', 'force': '1'},
        headers={'User-Agent': 'Mozilla/5.0'},
        timeout=30,
        verify=False
    )
    
    if resp.ok:
        data = resp.json()
        with open('/www/server/panel/data/plugin_list.json', 'w') as f:
            json.dump(data, f)
        print(f"  plugin_list.json: {len(data.get('list', []))} plugins")
    else:
        print(f"  plugin_list.json: FAILED (HTTP {resp.status_code})")
except Exception as e:
    print(f"  plugin_list.json: ERROR - {e}")
PLUGINLISTPATCH

ok "plugin_list.json created"

# --- STEP 9: Clear caches ---
echo ""
echo "[9/10] Clearing caches ..."
find "$PANEL_DIR" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null
find "$PANEL_DIR" -name "*.pyc" -delete 2>/dev/null
rm -f "$PANEL_DIR/data/plugin_bin.pl" 2>/dev/null
rm -f /tmp/bmac_* 2>/dev/null
ok "Caches cleared"

# --- STEP 10: Verify patches ---
echo ""
echo "[10/11] Verifying patches ..."
TOTAL=0
for f in class/config.py class_v2/config_v2.py class/panelAuth.py class_v2/panel_auth_v2.py class_v2/panel_plugin_v2.py class/public/PluginLoader.py class/PluginLoader.py script/check_auth.py; do
    count=$(grep -c "# \[PATCH\]" "$PANEL_DIR/$f" 2>/dev/null | tr -d '\n' || echo 0)
    [ -z "$count" ] && count=0
    TOTAL=$((TOTAL + count))
    if [ "$count" -gt 0 ]; then
        ok "$f: $count patch(es)"
    else
        fail "$f: NO patches!"
    fi
done
echo "  Total Python patches: $TOTAL"

# Check PluginLoader.so removed
if [ -f "$PANEL_DIR/class/PluginLoader.so" ]; then
    fail "PluginLoader.so still exists!"
else
    ok "PluginLoader.so removed"
fi

# Check plugin_list.json exists
if [ -f "$PANEL_DIR/data/plugin_list.json" ]; then
    ok "plugin_list.json exists"
else
    fail "plugin_list.json missing!"
fi

# --- STEP 11: Restart ---
echo ""
echo "[11/11] Restarting panel ..."
bt stop 2>/dev/null
sleep 2
bash "$PANEL_DIR/script/fix_pro.sh"
bt start 2>/dev/null
sleep 3
ok "Panel restarted"

echo ""
echo "=========================================="
echo " PRO Bypass v5 - Complete!"
echo "=========================================="
echo " - PRO vinh vien (permanent)"
echo " - Tat ca plugin PRO: Cai dat + su dung duoc"
echo " - Mirror download: aa.maxcdn.top"
echo " - PluginLoader.py (khong check license, khong circular import)"
echo " - Chay lai: bash /www/patch_pro.sh"
echo "=========================================="
echo ""
