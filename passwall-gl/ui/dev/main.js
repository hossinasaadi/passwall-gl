// Local preview: mounts the page with a fake GL RPC client and sample data.
import Vue from 'vue'
import Page from '../src/index.js'

const state = {
  global: {
    enabled: '1', node: 'n1', tcp_proxy_mode: 'proxy', udp_proxy_mode: 'proxy', chn_list: 'direct',
    localhost_proxy: '1', client_proxy: '1', use_direct_list: '1', use_proxy_list: '1', use_block_list: '1', use_gfw_list: '0',
  },
  nodes: [
    { id: 'n1', remarks: 'Frankfurt Reality', type: 'Xray', protocol: 'vless', address: '203.0.113.10', port: '443', group: '' },
    { id: 'n2', remarks: 'Amsterdam xHTTP', type: 'Xray', protocol: 'vless', address: 'ams.example.com', port: '443', group: '' },
    { id: 'n3', remarks: 'Tokyo Trojan', type: 'Xray', protocol: 'trojan', address: 'tyo.example.net', port: '8443', group: 'My Provider' },
    { id: 'n4', remarks: 'Helsinki SS', type: 'Xray', protocol: 'shadowsocks', address: '198.51.100.7', port: '8388', group: 'My Provider' },
    { id: 'n5', remarks: 'Smart routing', type: 'Xray', protocol: '_shunt', group: '', special: true },
  ],
  log: '2026-11-02 18:40:01: PassWall started\n2026-11-02 18:40:02: TCP node: Frankfurt Reality\n2026-11-02 18:40:02: DNS: chinadns-ng\n',
  subs: [
    { id: 'sub_main', remark: 'My Provider', url: 'https://provider.example.com/api/v1/client/subscribe?token=abc', update_week_mode: '8', update_interval_mode: '6', update_time_mode: '0:00', boot_update: '1', filter_keyword_mode: '5', user_agent: 'passwall', access_mode: '', domain_strategy: '', allowInsecure: '0', rem_traffic: '82.4 GB', expired_date: '2027-01-31' },
  ],
  filter: { filter_keyword_mode: '1', filter_discard_list: ['剩余流量', '套餐到期', '官网'], filter_keep_list: [] },
  updatingUntil: 0,
  rules: {
    direct_host: '# Sites that should not use the proxy\ngeosite:private\nexample-bank.com\nintranet.example.org\n',
    direct_ip: 'geoip:private\n192.168.0.0/16\n',
    proxy_host: 'geosite:youtube\ngithub.com\n',
    proxy_ip: 'geoip:telegram\n',
    block_host: 'geosite:category-ads-all\n',
    block_ip: '',
  },
}

const wait = (ms) => new Promise((r) => setTimeout(r, ms))

// Seeded random numbers (mulberry32), so screenshots come out the same each run.
let seed = 42
const rand = () => {
  seed = (seed + 0x6d2b79f5) | 0
  let t = Math.imul(seed ^ (seed >>> 15), 1 | seed)
  t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296
}
const remark = (n) => `Xray ${n.protocol}：[${n.remarks}]`

const handlers = {
  get_status: () => ({
    enabled: state.global.enabled === '1', tcp_status: state.global.enabled === '1', udp_status: state.global.enabled === '1',
    dns_mode_status: state.global.enabled === '1', node: state.global.node,
    node_remark: remark(state.nodes.find((n) => n.id === state.global.node) || {}),
    version: '26.10.29-1', xray_version: '26.10.31',
  }),
  get_global: () => ({ ...state.global }),
  set_global: ({ values }) => {
    for (const [k, v] of Object.entries(values)) state.global[k] = v === true ? '1' : v === false ? '0' : v
    return true
  },
  get_nodes: () => ({ nodes: state.nodes.map((n) => ({ ...n, remark: remark(n) })), current: state.global.node }),
  set_node: ({ id }) => ((state.global.node = id), true),
  ping_node: () => wait(400).then(() => ({ ping: rand() < 0.15 ? null : 20 + Math.floor(rand() * 300) })),
  urltest_node: () => wait(900).then(() => (rand() < 0.15 ? {} : { use_time: String(80 + rand() * 600) })),
  connect_status: ({ target }) => wait(500).then(() => (target === 'youtube' && rand() < 0.5 ? {} : { use_time: String(40 + rand() * 400) })),
  add_links: ({ links }) => {
    const lines = links.split('\n').filter(Boolean)
    if (lines.every((l) => /^https?:\/\//.test(l))) {
      throw new Error('That is a subscription address, not a share link. Add it on the Subscriptions tab.')
    }
    for (const line of lines) {
      const id = 'n' + (state.nodes.length + 1 + Math.floor(rand() * 1000))
      state.nodes.push({ id, remarks: line.slice(0, 24), type: 'Xray', protocol: line.split(':')[0], address: 'new.example.org', port: '443', group: '' })
    }
    return { added: lines.length }
  },
  get_subscriptions: () => {
    if (state.updatingUntil && Date.now() > state.updatingUntil) {
      state.updatingUntil = 0
      for (const s of state.subs) {
        if (!state.nodes.some((n) => n.group === s.remark)) {
          state.nodes.push({ id: 'n' + Date.now(), remarks: 'Tokyo 01', type: 'Xray', protocol: 'vless', address: 'tyo1.example.net', port: '443', group: s.remark })
        }
      }
    }
    const subs = state.subs.map((s) => ({ ...s, nodes: state.nodes.filter((n) => n.group === s.remark).length }))
    return { subscriptions: subs, filter: { ...state.filter }, updating: !!state.updatingUntil }
  },
  save_subscription: ({ id, values }) => {
    if (!values.remark) throw new Error('Give the subscription a name.')
    if (!/^https?:\/\//.test(values.url || '')) throw new Error('The subscription URL must start with http:// or https://')
    if (id) {
      Object.assign(state.subs.find((s) => s.id === id), values)
      return { id }
    }
    const sid = 'sub_' + rand().toString(36).slice(2, 7)
    state.subs.push({ id: sid, ...values })
    return { id: sid }
  },
  delete_subscription: ({ id }) => {
    const s = state.subs.find((x) => x.id === id)
    state.nodes = state.nodes.filter((n) => n.group !== s.remark)
    state.subs = state.subs.filter((x) => x.id !== id)
    return true
  },
  update_subscription: () => ((state.updatingUntil = Date.now() + 4000), true),
  update_all_subscriptions: () => ((state.updatingUntil = Date.now() + 4000), true),
  delete_subscription_nodes: ({ id }) => {
    const s = state.subs.find((x) => x.id === id)
    state.nodes = state.nodes.filter((n) => n.group !== s.remark)
    return true
  },
  delete_all_subscription_nodes: () => ((state.nodes = state.nodes.filter((n) => !state.subs.some((s) => s.remark === n.group))), true),
  set_subscribe_filter: ({ values }) => (Object.assign(state.filter, values), true),
  get_rules: () => ({ lists: { ...state.rules } }),
  save_rules: ({ lists }) => {
    for (const [name, text] of Object.entries(lists)) {
      const bad = text.split('\n').map((l) => l.trim()).find((l) => l && !l.startsWith('#') && /\s/.test(l))
      if (bad) throw new Error(`line "${bad}" is not valid.`)
      state.rules[name] = text
    }
    return true
  },
  delete_nodes: ({ ids }) => ((state.nodes = state.nodes.filter((n) => !ids.includes(n.id))), true),
  get_log: () => state.log,
  clear_log: () => ((state.log = ''), true),
  restart: () => true,
}

// Like PassWall's JSON encoder on the router: empty lists arrive as {}.
const luaJson = (v) => {
  if (Array.isArray(v)) return v.length ? v.map(luaJson) : {}
  if (v && typeof v === 'object') return Object.fromEntries(Object.entries(v).map(([k, x]) => [k, luaJson(x)]))
  return v
}

// Like GL's RPC layer: any null argument is rejected before the call.
const hasNull = (v) => v === null || (typeof v === 'object' && v !== null && Object.values(v).some(hasNull))

window.$rpcRequest = (kind, [, module, method, args]) => {
  if (hasNull(args)) return Promise.reject(new Error('Illegal parameter, operation failed. [-32602]'))
  const fn = module === 'passwall' && handlers[method]
  if (!fn) return Promise.resolve({ code: -1, error: 'unknown method ' + method })
  return wait(120)
    .then(() => fn(args || {}))
    .then((data) => ({ code: 0, data: luaJson(data) }), (e) => ({ code: -1, error: e.message }))
}

const params = new URLSearchParams(location.search)
if (params.get('shot')) document.body.classList.add('shot')

const vm = new Vue({ render: (h) => h(Page) }).$mount('#app')
const page = vm.$children[0]
if (params.get('tab')) page.current = params.get('tab')

// Start a view's tests once it has loaded, for screenshots with results.
const run = params.get('run')
if (run) {
  setTimeout(() => {
    // Tabs stay alive once opened, so pick the view by name, not position.
    const view = (name) => page.$children.find((c) => c.$options.name === name)
    if (run === 'probe') view('StatusView').probeAll()
    if (run === 'urltest') view('NodesView').testAll('url')
    if (run === 'edit') view('SubscriptionsView').startEdit(view('SubscriptionsView').subs[0])
  }, 500)
}
