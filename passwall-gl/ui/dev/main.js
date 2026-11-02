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
    { id: 'n3', remarks: 'Tokyo Trojan', type: 'Xray', protocol: 'trojan', address: 'tyo.example.net', port: '8443', group: 'sub_main' },
    { id: 'n4', remarks: 'Helsinki SS', type: 'Xray', protocol: 'shadowsocks', address: '198.51.100.7', port: '8388', group: 'sub_main' },
    { id: 'n5', remarks: 'Smart routing', type: 'Xray', protocol: '_shunt', group: '', special: true },
  ],
  log: '2026-11-02 18:40:01: PassWall started\n2026-11-02 18:40:02: TCP node: Frankfurt Reality\n2026-11-02 18:40:02: DNS: chinadns-ng\n',
}

const wait = (ms) => new Promise((r) => setTimeout(r, ms))
const remark = (n) => `Xray ${n.protocol}：[${n.remarks}]`

const handlers = {
  status: () => ({
    enabled: state.global.enabled === '1', tcp_status: state.global.enabled === '1', udp_status: state.global.enabled === '1',
    dns_mode_status: state.global.enabled === '1', node: state.global.node,
    node_remark: remark(state.nodes.find((n) => n.id === state.global.node) || {}),
    version: '26.10.29-1', xray_version: '26.3.27',
  }),
  get_global: () => ({ ...state.global }),
  set_global: ({ values }) => {
    for (const [k, v] of Object.entries(values)) state.global[k] = v === true ? '1' : v === false ? '0' : v
    return true
  },
  list_nodes: () => ({ nodes: state.nodes.map((n) => ({ ...n, remark: remark(n) })), current: state.global.node }),
  set_node: ({ id }) => ((state.global.node = id), true),
  ping_node: () => wait(400).then(() => ({ ping: Math.random() < 0.15 ? null : 20 + Math.floor(Math.random() * 300) })),
  urltest_node: () => wait(900).then(() => (Math.random() < 0.15 ? {} : { use_time: String(80 + Math.random() * 600) })),
  connect_status: ({ target }) => wait(500).then(() => (target === 'youtube' && Math.random() < 0.5 ? {} : { use_time: String(40 + Math.random() * 400) })),
  add_links: ({ links }) => {
    for (const line of links.split('\n').filter(Boolean)) {
      const id = 'n' + (state.nodes.length + 1 + Math.floor(Math.random() * 1000))
      state.nodes.push({ id, remarks: line.slice(0, 24), type: 'Xray', protocol: line.split(':')[0], address: 'new.example.org', port: '443', group: '' })
    }
    return true
  },
  delete_nodes: ({ ids }) => ((state.nodes = state.nodes.filter((n) => !ids.includes(n.id))), true),
  get_log: () => state.log,
  clear_log: () => ((state.log = ''), true),
  restart: () => true,
}

window.$rpcRequest = (kind, [, module, method, args]) => {
  const fn = module === 'passwall' && handlers[method]
  if (!fn) return Promise.resolve({ code: -1, error: 'unknown method ' + method })
  return wait(120)
    .then(() => fn(args || {}))
    .then((data) => ({ code: 0, data }))
}

new Vue({ render: (h) => h(Page) }).$mount('#app')
