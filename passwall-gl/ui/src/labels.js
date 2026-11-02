// Short, readable names for PassWall's node protocols. PassWall's own remark
// strings use its untranslated internal names (e.g. "_shunt"), so the page
// builds labels from these instead.
const PROTOCOLS = {
  vless: 'VLESS',
  vmess: 'VMess',
  trojan: 'Trojan',
  shadowsocks: 'SS',
  socks: 'SOCKS',
  http: 'HTTP',
  wireguard: 'WG',
  hysteria2: 'HY2',
  _shunt: 'Shunt',
  _balancing: 'Balancer',
  _urltest: 'URLTest',
  _iface: 'Interface',
}

export function typeLabel(n) {
  return PROTOCOLS[n.protocol] || n.protocol || n.type || ''
}

export function nodeLabel(n) {
  const type = typeLabel(n)
  return type ? `${type} · ${n.remarks}` : n.remarks
}
