import json
import os
from urllib.error import URLError
from urllib.request import Request, urlopen

import webview

from .config import load_config, save_config
from .frontmost import running_apps

CONFIG_PATH = os.path.join(os.path.dirname(os.path.dirname(__file__)), "config.json")
CONTROL_URL = "http://127.0.0.1:17863"
GESTURES = ["longPress", "single", "double", "triple", "up", "down", "left", "right"]
KEY_CHOICES = ["", "voice", "scroll-up", "scroll-down", "enter", "esc", "tab", "shift+tab",
               "up", "down", "left", "right",
               "cmd+a;backspace", "ctrl+u", "cmd+a", "cmd+enter", "space", "backspace"]
VIBRATION_EVENTS = [
    ("taskComplete", "任务完成"),
    ("needsAttention", "需要确认"),
    ("error", "执行失败"),
]
VIBRATION_CHOICES = [
    ("off", "关闭"),
    ("strong", "强力"),
    ("continuous", "持续"),
    ("gradient", "渐变"),
]


def request_control(path, payload=None, open_request=urlopen):
    data = None if payload is None else json.dumps(payload).encode()
    request = Request(
        CONTROL_URL + path,
        data=data,
        headers={"Content-Type": "application/json"} if data is not None else {},
        method="POST" if data is not None else "GET",
    )
    with open_request(request, timeout=2) as response:
        return json.loads(response.read())


class Api:
    def get_state(self):
        return {"config": load_config(CONFIG_PATH), "running": running_apps(),
                "gestures": GESTURES, "keys": KEY_CHOICES,
                "vibrationEvents": VIBRATION_EVENTS,
                "vibrationChoices": VIBRATION_CHOICES}

    def save(self, config_json):
        cfg = json.loads(config_json)
        save_config(CONFIG_PATH, cfg)
        return True

    def connection(self):
        try:
            return request_control("/connection")
        except (OSError, URLError, ValueError):
            return {
                "status": "offline",
                "connected": False,
                "device": None,
                "devices": [],
                "lastError": "Ring-desktop 主程序未运行",
            }

    def scan(self):
        return request_control("/connection/scan", {})

    def connect(self, address, name):
        return request_control(
            "/connection/connect", {"address": address, "name": name}
        )

    def disconnect(self):
        return request_control("/connection/disconnect", {})


HTML = """
<!doctype html><html><head><meta charset="utf-8"><style>
body{font:14px -apple-system;margin:16px;color:#222}
h3{margin:18px 0 6px} select{margin:2px} .app{border:1px solid #ddd;border-radius:8px;padding:10px;margin:8px 0}
.row{display:flex;gap:8px;align-items:center;margin:3px 0} .row label{width:90px}
.section{font-size:12px;font-weight:600;color:#666;margin:12px 0 5px;border-top:1px solid #eee;padding-top:9px}
button{padding:6px 12px;border-radius:6px;border:1px solid #aaa;background:#f6f6f6;cursor:pointer}
.connection{padding:0 0 14px;border-bottom:1px solid #ddd}.connection-head{display:flex;align-items:center;gap:8px;margin-bottom:10px}
.connection-head h3{margin:0}.dot{width:9px;height:9px;border-radius:50%;background:#999}.dot.on{background:#28a745}
.device-line{display:flex;gap:8px;align-items:center}.device-line select{flex:1;min-width:0;height:30px}
.meta{font-size:12px;color:#666;margin-top:7px;min-height:16px;overflow-wrap:anywhere}.error{color:#b42318}
</style></head><body>
<h2>Ring 配置</h2>
<section class="connection">
  <div class="connection-head"><span id="connDot" class="dot"></span><h3>戒指连接</h3><span id="connStatus">正在读取…</span></div>
  <div class="device-line">
    <select id="devices"></select>
    <button id="scanButton" onclick="scanRing()">扫描</button>
    <button id="connectButton" onclick="connectRing()">连接</button>
    <button onclick="disconnectRing()">断开</button>
  </div>
  <div id="connMeta" class="meta"></div>
</section>
<div id="apps"></div>
<h3>添加 app</h3><select id="add"></select><button onclick="addApp()">添加</button>
<p><button onclick="save()">保存</button> <span id="msg"></span></p>
<script>
let S=null;
const STATUS={connected:'已连接',connecting:'正在连接',scanning:'正在扫描',ready:'请选择戒指',disconnected:'未连接','not found':'未发现戒指',error:'连接失败',offline:'主程序未运行',starting:'正在启动'};
async function load(){ S=await window.pywebview.api.get_state(); render(); await refreshConnection(); setInterval(refreshConnection,1000); }
async function refreshConnection(){
  const c=await window.pywebview.api.connection();
  document.getElementById('connStatus').innerText=STATUS[c.status]||c.status;
  document.getElementById('connDot').className='dot'+(c.connected?' on':'');
  const select=document.getElementById('devices'), previous=select.value; select.innerHTML='';
  const devices=[...(c.devices||[])];
  if(c.device&&!devices.some(d=>d.address===c.device.address)) devices.unshift({...c.device,rssi:null});
  if(!devices.length){ const o=document.createElement('option'); o.value=''; o.text='尚未扫描到戒指'; select.appendChild(o); }
  for(const d of devices){ const o=document.createElement('option'); o.value=d.address; o.dataset.name=d.name;
    o.text=d.name+(d.rssi===null||d.rssi===undefined?'':'  '+d.rssi+' dBm'); select.appendChild(o); }
  if(devices.some(d=>d.address===previous)) select.value=previous;
  else if(c.device) select.value=c.device.address;
  const meta=c.device?c.device.name+' · '+c.device.address:(c.lastError||'');
  const metaEl=document.getElementById('connMeta'); metaEl.innerText=c.lastError||meta; metaEl.className='meta'+(c.lastError?' error':'');
  document.getElementById('scanButton').disabled=c.status==='scanning';
  document.getElementById('connectButton').disabled=!select.value;
}
async function scanRing(){ await window.pywebview.api.scan(); await refreshConnection(); }
async function connectRing(){ const s=document.getElementById('devices'),o=s.options[s.selectedIndex]; if(!o||!s.value)return;
  await window.pywebview.api.connect(s.value,o.dataset.name); await refreshConnection(); }
async function disconnectRing(){ await window.pywebview.api.disconnect(); await refreshConnection(); }
function render(){
  const apps=document.getElementById('apps'); apps.innerHTML='';
  for(const b of Object.keys(S.config)){ apps.appendChild(card(b, S.config[b])); }
  const add=document.getElementById('add'); add.innerHTML='';
  for(const a of S.running){ const o=document.createElement('option');
    o.value=a.bundle; o.text=a.name+' ('+a.bundle+')'; add.appendChild(o); }
}
function card(bundle, prof){
  const d=document.createElement('div'); d.className='app';
  d.innerHTML='<b>'+bundle+'</b>';
  for(const g of S.gestures){
    const a=prof[g]||{}; const cur=a.type==='voice'?'voice':(a.type==='scroll'?'scroll-'+a.value:(a.value||''));
    const opts=S.keys.map(k=>'<option '+(k===cur?'selected':'')+' value="'+k+'">'+(k==='voice'?'🎙 语音听写':k==='scroll-up'?'⬆ 上滚':k==='scroll-down'?'⬇ 下滚':(k||'（不绑）'))+'</option>').join('');
    const row=document.createElement('div'); row.className='row';
    row.innerHTML='<label>'+g+'</label><select data-b="'+bundle+'" data-g="'+g+'">'+opts+'</select>';
    d.appendChild(row);
  }
  const heading=document.createElement('div'); heading.className='section'; heading.innerText='事件震动'; d.appendChild(heading);
  const vibration=prof.vibration||{};
  for(const [event,label] of S.vibrationEvents){
    const cur=vibration[event]||'off';
    const opts=S.vibrationChoices.map(([value,name])=>'<option '+(value===cur?'selected':'')+' value="'+value+'">'+name+'</option>').join('');
    const row=document.createElement('div'); row.className='row';
    row.innerHTML='<label>'+label+'</label><select data-b="'+bundle+'" data-event="'+event+'">'+opts+'</select>';
    d.appendChild(row);
  }
  return d;
}
function collect(){
  const cfg={}; document.querySelectorAll('select[data-g]').forEach(s=>{
    const b=s.dataset.b,g=s.dataset.g; cfg[b]=cfg[b]||{};
    if(s.value==='voice') cfg[b][g]={type:'voice'};
    else if(s.value==='scroll-up') cfg[b][g]={type:'scroll',value:'up'};
    else if(s.value==='scroll-down') cfg[b][g]={type:'scroll',value:'down'};
    else if(s.value) cfg[b][g]={type:'key',value:s.value};
  });
  document.querySelectorAll('select[data-event]').forEach(s=>{
    const b=s.dataset.b,event=s.dataset.event; cfg[b]=cfg[b]||{};
    cfg[b].vibration=cfg[b].vibration||{}; cfg[b].vibration[event]=s.value;
  });
  return cfg;
}
function addApp(){ const b=document.getElementById('add').value;
  if(!S.config[b]) S.config[b]={}; render(); }
async function save(){ const merged=collect();
  if(!merged.default) merged.default=S.config.default||{};
  await window.pywebview.api.save(JSON.stringify(merged));
  document.getElementById('msg').innerText='已保存 ✓'; }
window.addEventListener('pywebviewready', load);
</script></body></html>
"""


def main():
    webview.create_window("Ring 配置", html=HTML, js_api=Api(), width=560, height=720)
    webview.start()


if __name__ == "__main__":
    main()
