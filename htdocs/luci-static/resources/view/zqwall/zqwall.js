'use strict';
'require view';
'require ui';
'require rpc';
'require uci';

var conf = 'zqwall';
var sec = 'settings';

var callSvc = rpc.declare({
    object: 'rc', method: 'init',
    params: ['name', 'action'],
    expect: { result: 0 }
});

var callStatus = rpc.declare({
    object: 'service', method: 'list',
    params: ['name'],
    expect: {}
});

function parseVless(link) {
    try {
        link = link.trim();
        if (!link.startsWith('vless://')) return null;
        var rest = link.substring(8);
        var h = rest.indexOf('#');
        var name = h >= 0 ? decodeURIComponent(rest.substring(h + 1)) : '';
        var url = h >= 0 ? rest.substring(0, h) : rest;
        var a = url.indexOf('@');
        if (a < 0) return null;
        var uuid = url.substring(0, a);
        var q = url.indexOf('?');
        var hp = q >= 0 ? url.substring(a + 1, q) : url.substring(a + 1);
        var qs = q >= 0 ? url.substring(q + 1) : '';
        var parts = hp.split(':');
        var params = {};
        qs.split('&').forEach(function(p) {
            var e = p.indexOf('=');
            if (e >= 0) params[p.substring(0, e)] = decodeURIComponent(p.substring(e + 1));
        });
        return {
            uuid: uuid, address: parts[0], port: parts[1] || '443',
            flow: params.flow || 'xtls-rprx-vision', sni: params.sni || '',
            pbk: params.pbk || '', sid: params.sid || '', fp: params.fp || 'chrome',
            spx: params.spx || '/', name: name
        };
    } catch (e) { return null; }
}

function esc(s) { return String(s || '').replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;'); }
function val(id) { var e = document.getElementById(id); return e ? e.value : ''; }
function setVal(id, v) { var e = document.getElementById(id); if (e) e.value = v; }
function chk(id) { var e = document.getElementById(id); return e ? e.checked : false; }

function saveConfig() {
    uci.set(conf, sec, 'zqwall');
    ['uuid','address','port','flow','sni','pbk','sid','fp','spx',
     'tproxy_port','dns_port','mixed_port','dns_server'].forEach(function(f) {
        uci.set(conf, sec, f, val('zw-'+f));
    });
    uci.set(conf, sec, 'enabled', chk('zw-enabled') ? '1' : '0');
    uci.save();
    ui.addNotification(null, 'Saved', 'info');
}

return view.extend({
    load: function() { return uci.load(conf); },
    render: function() {

        var g = function(o, d) { return uci.get(conf, sec, o) || d; };

        var html = '';

        // STATUS BAR
        html += '<div id="zw-status" class="cbi-section" style="padding:12px;margin-bottom:12px">';
        html += '<strong>Status:</strong> <span id="zw-badge" style="padding:3px 10px;border-radius:3px;font-weight:bold;color:#fff;background:#888">checking...</span>';
        html += ' &nbsp; ';
        html += '<button class="cbi-button cbi-button-apply" id="btn-start">Start</button> ';
        html += '<button class="cbi-button cbi-button-reset" id="btn-stop">Stop</button> ';
        html += '<button class="cbi-button cbi-button-reload" id="btn-reload">Reload</button>';
        html += '</div>';

        // VLESS IMPORT
        html += '<div class="cbi-section" style="padding:12px;margin-bottom:12px">';
        html += '<label style="font-weight:bold">Import VLESS Link:</label> ';
        html += '<input type="text" id="vless-input" class="cbi-input-text" placeholder="vless://..." style="width:55%;margin:0 8px"> ';
        html += '<button class="cbi-button cbi-button-apply" id="btn-import">Import</button>';
        html += '</div>';

        // FORM
        function row(t, id, v, ph, fl, sel) {
            var inp;
            if (fl) inp = '<input type="checkbox" id="'+id+'"'+(v==='1'?' checked':'')+'>';
            else if (sel) { inp = '<select id="'+id+'" class="cbi-input-select">'+sel.map(function(x){return '<option value="'+x+'"'+(x===v?' selected':'')+'>'+x+'</option>';}).join('')+'</select>'; }
            else inp = '<input type="text" id="'+id+'" class="cbi-input-text" value="'+esc(v)+'" placeholder="'+(ph||'')+'">';
            return '<div class="cbi-value"><label class="cbi-value-title">'+t+'</label><div class="cbi-value-field">'+inp+'</div></div>';
        }

        html += '<fieldset class="cbi-section"><legend>VLESS Server</legend>';
        html += row('Enable', 'zw-enabled', g('enabled','0'), '', true);
        html += row('UUID', 'zw-uuid', g('uuid',''));
        html += row('Address', 'zw-address', g('address',''), 'server.example.com');
        html += row('Port', 'zw-port', g('port','443'), '443');
        html += row('Flow', 'zw-flow', g('flow','xtls-rprx-vision'), '', false, ['xtls-rprx-vision','xtls-rprx-vision-udp443']);
        html += row('SNI', 'zw-sni', g('sni',''), 'www.whatsapp.com');
        html += row('Public Key', 'zw-pbk', g('pbk',''), 'Reality PBK');
        html += row('Short ID', 'zw-sid', g('sid',''));
        html += row('Fingerprint', 'zw-fp', g('fp','chrome'), '', false, ['chrome','firefox','safari','ios','edge','random']);
        html += row('SpiderX', 'zw-spx', g('spx','/'), '/');
        html += '</fieldset>';

        html += '<fieldset class="cbi-section"><legend>Ports</legend>';
        html += row('TPROXY Port', 'zw-tproxy_port', g('tproxy_port','10105'));
        html += row('DNS Port', 'zw-dns_port', g('dns_port','10153'));
        html += row('SOCKS5 Port', 'zw-mixed_port', g('mixed_port','2080'));
        html += row('DNS Server', 'zw-dns_server', g('dns_server','https://1.1.1.1/dns-query'));
        html += '</fieldset>';

        // BUTTONS
        html += '<div class="cbi-page-actions">';
        html += '<button class="cbi-button cbi-button-save" id="btn-save">Save</button> ';
        html += '<button class="cbi-button cbi-button-apply" id="btn-apply">Save & Reload</button>';
        html += '</div>';

        var container = document.createElement('div');
        container.innerHTML = html;

        setTimeout(function() {
            function updateStatus() {
                callStatus('zqwall').then(function(info) {
                    var running = false;
                    if (info && info.zqwall && info.zqwall.instances)
                        for (var k in info.zqwall.instances)
                            if (info.zqwall.instances[k].running) running = true;
                    var b = document.getElementById('zw-badge');
                    if (b) { b.textContent = running ? 'RUNNING' : 'STOPPED'; b.style.background = running ? '#22aa44' : '#cc3333'; }
                    var s = document.getElementById('btn-start');
                    var p = document.getElementById('btn-stop');
                    var r = document.getElementById('btn-reload');
                    if (s) s.disabled = running;
                    if (p) p.disabled = !running;
                    if (r) r.disabled = !running;
                });
            }
            updateStatus();

            document.getElementById('btn-import').onclick = function() {
                var d = parseVless(val('vless-input'));
                if (!d) { ui.addNotification(null, 'Invalid link', 'error'); return; }
                setVal('zw-uuid', d.uuid); setVal('zw-address', d.address);
                setVal('zw-port', d.port); setVal('zw-flow', d.flow);
                setVal('zw-sni', d.sni); setVal('zw-pbk', d.pbk);
                setVal('zw-sid', d.sid); setVal('zw-fp', d.fp);
                setVal('zw-spx', d.spx); setVal('vless-input', '');
                ui.addNotification(null, 'Imported: ' + (d.name || d.address), 'info');
            };

            document.getElementById('btn-start').onclick = function() {
                callSvc('zqwall', 'start').then(function() {
                    ui.addNotification(null, 'Starting...', 'info');
                    setTimeout(updateStatus, 2000);
                });
            };
            document.getElementById('btn-stop').onclick = function() {
                callSvc('zqwall', 'stop').then(function() {
                    ui.addNotification(null, 'Stopped', 'info');
                    setTimeout(updateStatus, 1000);
                });
            };
            document.getElementById('btn-reload').onclick = function() {
                callSvc('zqwall', 'reload').then(function() {
                    ui.addNotification(null, 'Reloading...', 'info');
                    setTimeout(updateStatus, 2000);
                });
            };
            document.getElementById('btn-save').onclick = function() { saveConfig(); };
            document.getElementById('btn-apply').onclick = function() {
                saveConfig();
                callSvc('zqwall', 'reload').then(function() {
                    ui.addNotification(null, 'Saved & Reloaded', 'info');
                    setTimeout(updateStatus, 2000);
                });
            };
        }, 100);

        return container;
    }
});
