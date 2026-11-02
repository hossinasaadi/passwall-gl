// Calls go through GL's own RPC client, which adds the logged-in session.
// The backend answers {code: 0, data} or {code: -1, error}.
export function rpc(method, args = {}) {
  const request = window.$rpcRequest
  if (typeof request !== 'function') {
    return Promise.reject(new Error('GL RPC client not found'))
  }
  return request('call', ['sid', 'passwall', method, args]).then((res) => {
    if (!res || res.code !== 0) throw new Error((res && res.error) || 'Request failed')
    return res.data
  })
}
