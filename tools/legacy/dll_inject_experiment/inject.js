// E听说助手 · 页面注入脚本（自主实现）
//
// 作用：在 E听说 页面上下文里拦截成绩相关请求/响应，按软件下发的规则改写。
// 规则来源：window.__ETS_RULES__（由 DLL 从软件远程拉取后注入）
// 结构：
//   { scoreOn, target, full, cats: {category: score}, timeOn, timeOffsetSec, v }
// 若未注入规则或规则关闭，本脚本不做任何改写（完全透明）。
(function () {
  if (window.__ets_helper_installed__) return;
  window.__ets_helper_installed__ = true;

  function rules() {
    var r = window.__ETS_RULES__;
    if (!r || typeof r !== 'object') return null;
    return r;
  }
  function log() {
    var r = rules();
    if (!r || !r.debug) return;
    try { console.log('[ETS-Helper]', Array.prototype.join.call(arguments, ' ')); } catch (e) {}
  }
  function notify() {
    try {
      var r = rules() || {};
      r.count = (r.count || 0) + 1;
      r.lastAt = Date.now();
      window.__ETS_RULES__ = r;
    } catch (e) {}
  }

  // base64 <-> UTF-8（E听说 请求体是 base64(JSON)）
  function b64ToUtf8(b64) {
    var bin = atob(b64.replace(/\s+/g, ''));
    var bytes = new Uint8Array(bin.length);
    for (var i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
    return new TextDecoder('utf-8').decode(bytes);
  }
  function utf8ToB64(str) {
    var bytes = new TextEncoder().encode(str);
    var bin = '';
    for (var i = 0; i < bytes.length; i += 0x8000) {
      bin += String.fromCharCode.apply(null, bytes.subarray(i, i + 0x8000));
    }
    return btoa(bin);
  }

  function round1(v) { return Math.round(v * 10) / 10; }
  function num(v) {
    if (v === null || v === undefined) return null;
    if (typeof v === 'number') return v;
    var n = parseFloat(v);
    return isNaN(n) ? null : n;
  }
  // 保留原字段类型（安卓字符串 / Win 数字）
  function typed(oldVal, value) {
    if (typeof oldVal === 'string') {
      var frac = (oldVal.split('.')[1] || '').length;
      return frac >= 3 ? value.toFixed(frac) : value.toFixed(1);
    }
    if (typeof oldVal === 'boolean') return oldVal;
    return value;
  }

  // 计算某道小题应得的分数
  function calcScore(cat, mark, full) {
    var r = rules();
    if (!r) return null;
    if (r.cats && r.cats[cat] !== undefined && r.cats[cat] !== null) return num(r.cats[cat]);
    if (!full || full <= 0) return mark;
    return round1(mark * num(r.target || 0) / full);
  }

  // ---- 明细对象：total_score 与四分项同步 ----
  function applyDetail(detail, newScore) {
    var total = num(detail.total_score) || 0;
    if (detail.total_score !== undefined) {
      detail.total_score = typed(detail.total_score, newScore);
    }
    if (detail.real_score !== undefined) {
      detail.real_score = typed(detail.real_score, newScore);
    }
    ['fluency_score', 'accuracy_score', 'integrity_score', 'standard_score'].forEach(function (k) {
      if (detail[k] === undefined) return;
      var v = num(detail[k]);
      if (v === null) return;
      // 与总分同比例缩放；原分为 0 时等值填充，避免详情页自相矛盾
      detail[k] = typed(detail[k], total > 0 ? round1(v * newScore / total) : newScore);
    });
  }

  // ---- 请求体改写：sync-v2 ----
  function rewriteRequestBody(text) {
    var r = rules();
    if (!r || !r.scoreOn && !r.timeOn) return null;
    var env;
    try { env = JSON.parse(text); } catch (e) { return null; }
    if (!env || typeof env.body !== 'string') return null;
    var inner;
    try { inner = JSON.parse(b64ToUtf8(env.body)); } catch (e) { return null; }
    if (!Array.isArray(inner)) return null;

    var full = num(r.full) || 0;
    var changed = false;
    inner.forEach(function (item) {
      if (!item || !item.params) return;
      var p = item.params;
      var isSync = String(item.r || '').indexOf('audio/sync-v2') >= 0;
      if (r.scoreOn && isSync) {
        var detail = null;
        try { detail = typeof p.score_detail === 'string' ? JSON.parse(p.score_detail) : p.score_detail; } catch (e) {}
        var mark = num(p.question_type_score) || (r.marks && r.marks[p.entity_id] !== undefined ? num(r.marks[p.entity_id]) : null);
        if (mark && mark > 0) {
          if (!full) full = mark; // 兜底：按本题满分给
          var cat = detail && detail.category ? detail.category : '';
          var ns = calcScore(cat, mark, full);
          if (ns !== null) {
            if (detail) { applyDetail(detail, ns); p.score_detail = JSON.stringify(detail); }
            p.score = typed(p.score, ns);
            if (p.real_score !== undefined) p.real_score = typed(p.real_score, ns);
            changed = true;
            log('改写提交', cat, mark, '->', ns);
          }
        }
      }
      if (r.timeOn && p.client_time && r.timeOffsetSec) {
        var t = new Date(p.client_time.replace(/-/g, '/').replace('T', ' ').replace(' ', ' '));
        if (!isNaN(t.getTime())) {
          var nt = new Date(t.getTime() + num(r.timeOffsetSec) * 1000);
          var f = function (n) { return (n < 10 ? '0' : '') + n; };
          p.client_time = nt.getFullYear() + '-' + f(nt.getMonth() + 1) + '-' + f(nt.getDate()) + ' ' +
            f(nt.getHours()) + ':' + f(nt.getMinutes()) + ':' + f(nt.getSeconds());
          changed = true;
          log('改写完成时刻 ->', p.client_time);
        }
      }
    });
    if (!changed) return null;
    env.body = utf8ToB64(JSON.stringify(inner));
    notify();
    return JSON.stringify(env);
  }

  // ---- 响应改写：成绩详情 / 作业列表 ----
  function rewriteResponseText(text, path) {
    var r = rules();
    if (!r || !r.scoreOn) return null;
    if (path.indexOf('get-score-detail') < 0 && path.indexOf('g/set/list') < 0 &&
        path.indexOf('sync-v2') < 0 && path.indexOf('set/list') < 0) return null;
    var root;
    try { root = JSON.parse(text); } catch (e) { return null; }
    if (!Array.isArray(root)) return null;

    var changed = false;
    root.forEach(function (item) {
      var body = item && item.body;
      if (!body || typeof body !== 'object') return;

      // 作业列表：body.score[].point / total_point
      if (Array.isArray(body.score)) {
        var full = 0;
        body.score.forEach(function (s) { if (s && s.total_point) full += num(s.total_point) || 0; });
        body.score.forEach(function (s) {
          if (!s) return;
          var mark = num(s.total_point) || 0;
          if (mark <= 0) return;
          var ns = calcScore('', mark, full);
          if (ns === null) return;
          if (s.point !== undefined) { s.point = typed(s.point, ns); changed = true; }
          if (s.avg_point !== undefined) { s.avg_point = typed(s.avg_point, ns); }
          log('列表分数', mark, '->', ns);
        });
      }

      // 成绩详情：body.score[].real_score / detail(JSON 字符串)
      if (Array.isArray(body.score)) {
        var f2 = 0;
        body.score.forEach(function (s) { if (s && s.total_point) f2 += num(s.total_point) || 0; });
        var sum = 0;
        body.score.forEach(function (s) {
          if (!s) return;
          var mark = num(s.total_point) || 0;
          if (mark <= 0) return;
          var detail = null;
          if (typeof s.detail === 'string') { try { detail = JSON.parse(s.detail); } catch (e) {} }
          else if (s.detail && typeof s.detail === 'object') detail = s.detail;
          var cat = detail && detail.category ? detail.category : '';
          var ns = calcScore(cat, mark, f2);
          if (ns === null) return;
          if (s.real_score !== undefined) { s.real_score = typed(s.real_score, ns); }
          if (s.standard_score !== undefined) { s.standard_score = typed(s.standard_score, ns); }
          if (detail) { applyDetail(detail, ns); s.detail = JSON.stringify(detail); }
          sum += ns;
          changed = true;
          log('详情分数', cat, mark, '->', ns);
        });
        if (body.avg_point !== undefined && changed) {
          body.avg_point = typed(body.avg_point, round1(sum));
        }
        var dim = body.dimension_score;
        if (dim && Array.isArray(body.score) && body.score.length) {
          var avg = round1(sum / body.score.length);
          ['fluency_score', 'integrity_score', 'accuracy_score', 'standard_score', 'stress_pronunciation_score'].forEach(function (k) {
            if (dim[k] !== undefined) dim[k] = typed(dim[k], avg);
          });
        }
      }

      // sync-v2 提交响应：body.point / real_score
      if (body.point !== undefined && body.total_point !== undefined) {
        var mark2 = num(body.total_point) || 0;
        var ns2 = calcScore('', mark2, num(r.full) || mark2);
        if (ns2 !== null) {
          body.point = typed(body.point, ns2);
          if (body.real_score !== undefined) body.real_score = typed(body.real_score, ns2);
          changed = true;
          log('提交回执', mark2, '->', ns2);
        }
      }
    });
    if (!changed) return null;
    notify();
    return JSON.stringify(root);
  }

  // ================= XHR 拦截 =================
  var origOpen = XMLHttpRequest.prototype.open;
  var origSend = XMLHttpRequest.prototype.send;
  var origSetHeader = XMLHttpRequest.prototype.setRequestHeader;

  XMLHttpRequest.prototype.open = function (method, url) {
    this.__ets_url = String(url);
    this.__ets_method = String(method || 'GET');
    return origOpen.apply(this, arguments);
  };

  XMLHttpRequest.prototype.send = function (body) {
    try {
      var r = rules();
      if (r && (r.scoreOn || r.timeOn) && typeof body === 'string' && this.__ets_url &&
          this.__ets_url.indexOf('api.ets100.com') >= 0) {
        var nb = rewriteRequestBody(body);
        if (nb) {
          log('请求体已改写', this.__ets_url.split('?')[0]);
          body = nb;
        }
      }
    } catch (e) { log('请求改写异常', e && e.message); }
    return origSend.call(this, body);
  };

  // 响应：getter 拦截（responseText / response）
  var descText = Object.getOwnPropertyDescriptor(XMLHttpRequest.prototype, 'responseText');
  var descResp = Object.getOwnPropertyDescriptor(XMLHttpRequest.prototype, 'response');
  function tryRewriteResp(xhr) {
    try {
      var url = xhr.__ets_url || '';
      if (!url || url.indexOf('api.ets100.com') < 0) return null;
      var t = (xhr.responseType === '' || xhr.responseType === 'text') ? descText.get.call(xhr) : null;
      if (typeof t !== 'string' || !t) return null;
      var nt = rewriteResponseText(t, url);
      if (nt) log('响应已改写', url.split('?')[0]);
      return nt;
    } catch (e) { return null; }
  }
  if (descText && descText.get) {
    Object.defineProperty(XMLHttpRequest.prototype, 'responseText', {
      get: function () { return tryRewriteResp(this) || descText.get.call(this); },
      set: descText.set,
      configurable: true,
      enumerable: descText.enumerable,
    });
  }
  if (descResp && descResp.get) {
    Object.defineProperty(XMLHttpRequest.prototype, 'response', {
      get: function () {
        var fixed = tryRewriteResp(this);
        if (fixed !== null) return fixed;
        return descResp.get.call(this);
      },
      set: descResp.set,
      configurable: true,
      enumerable: descResp.enumerable,
    });
  }

  // ================= fetch 拦截 =================
  if (typeof window.fetch === 'function') {
    var origFetch = window.fetch;
    window.fetch = function (input, init) {
      try {
        var r = rules();
        var url = typeof input === 'string' ? input : (input && input.url) || '';
        if (r && (r.scoreOn || r.timeOn) && url.indexOf('api.ets100.com') >= 0 && init && typeof init.body === 'string') {
          var nb = rewriteRequestBody(init.body);
          if (nb) { init = Object.assign({}, init, { body: nb }); log('fetch 请求已改写'); }
        }
      } catch (e) {}
      return origFetch.call(this, input, init).then(function (resp) {
        try {
          var r = rules();
          if (!r || !r.scoreOn || url.indexOf('api.ets100.com') < 0) return resp;
          var ct = resp.headers && resp.headers.get && (resp.headers.get('content-type') || '');
          if (ct.indexOf('json') < 0) return resp;
          return resp.clone().text().then(function (t) {
            var nt = rewriteResponseText(t, url);
            if (!nt) return resp;
            return new Response(nt, {
              status: resp.status,
              statusText: resp.statusText,
              headers: resp.headers,
            });
          }).catch(function () { return resp; });
        } catch (e) { return resp; }
      });
    };
  }

  // 汇报给 DLL（若页面里存在该桥接则用，否则忽略）
  log('注入完成 v=' + (rules() ? rules().v : 'no-rules'));
})();