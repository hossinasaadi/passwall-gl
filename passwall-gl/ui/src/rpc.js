// PassWall's JSON encoder writes an empty Lua table as {}, so a list with
// nothing in it arrives as an object. Use this wherever a list is expected.
export function asList(v) {
  return Array.isArray(v) ? v : []
}

// GL's RPC layer rejects any null argument with -32602 ("Illegal
// parameter"), so null and undefined values are left out of every call.
function withoutNulls(v) {
  if (Array.isArray(v)) return v.filter((x) => x != null).map(withoutNulls)
  if (v && typeof v === 'object') {
    const out = {}
    for (const [k, x] of Object.entries(v)) if (x != null) out[k] = withoutNulls(x)
    return out
  }
  return v
}

// Calls go through GL's own RPC client, which adds the logged-in session.
// The backend answers {code: 0, data} or {code: -1, error}.
export function rpc(method, args = {}) {
  const request = window.$rpcRequest
  if (typeof request !== 'function') {
    return Promise.reject(new Error('GL RPC client not found'))
  }
  return request('call', ['sid', 'passwall', method, withoutNulls(args)]).then((res) => {
    if (!res || res.code !== 0) throw new Error((res && res.error) || 'Request failed')
    return res.data
  })
}
