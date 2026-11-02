<template>
  <div>
    <div v-if="error" class="pw-error">{{ error }}</div>

    <section v-if="adding" class="pw-card">
      <h3 class="pw-card-title"><span>Add nodes from share links</span></h3>
      <p class="pw-row-help">
        One link per line: vless://, vmess://, trojan://, ss://, socks://, hysteria2:// and similar.
      </p>
      <textarea v-model="links" class="pw-textarea" spellcheck="false" placeholder="vless://…"></textarea>
      <div class="pw-toolbar">
        <input v-model.trim="group" class="pw-input" placeholder="Group (optional)" maxlength="64" />
        <span class="pw-spacer"></span>
        <button type="button" class="pw-btn" @click="adding = false">Cancel</button>
        <button type="button" class="pw-btn pw-btn-primary" :disabled="busy || !links.trim()" @click="addLinks">Add</button>
      </div>
    </section>

    <section class="pw-card">
      <div class="pw-toolbar">
        <button type="button" class="pw-btn pw-btn-primary" @click="adding = !adding">Add from links</button>
        <button type="button" class="pw-btn" :disabled="testing || !visible.length" @click="testAll('ping')">TCPing all</button>
        <button type="button" class="pw-btn" :disabled="testing || !visible.length" @click="testAll('url')">URL test all</button>
        <button type="button" class="pw-btn pw-btn-danger" :disabled="busy || !selectedIds.length" @click="removeSelected">
          Delete selected<span v-if="selectedIds.length"> ({{ selectedIds.length }})</span>
        </button>
        <span class="pw-spacer"></span>
        <input v-model.trim="filter" class="pw-input" type="search" placeholder="Search nodes" />
      </div>

      <p v-if="loaded && !nodes.length" class="pw-muted pw-empty">No nodes yet. Add some from share links or a subscription.</p>

      <div v-for="g in groups" :key="g.name" class="pw-group">
        <div class="pw-group-name">{{ g.name }} <span class="pw-muted">({{ g.nodes.length }})</span></div>
        <div class="pw-table-wrap">
          <table class="pw-table">
            <thead>
              <tr>
                <th class="pw-col-check">
                  <input type="checkbox" :checked="allSelected(g)" aria-label="Select group" @change="selectGroup(g, $event.target.checked)" />
                </th>
                <th>Remarks</th>
                <th class="pw-col-type">Type</th>
                <th class="pw-col-addr">Address</th>
                <th class="pw-num pw-col-ms">TCPing</th>
                <th class="pw-num pw-col-ms">URL test</th>
                <th class="pw-col-actions"></th>
              </tr>
            </thead>
            <tbody>
              <tr v-for="n in g.nodes" :key="n.id" :class="{ 'is-current': n.id === current }">
                <td class="pw-col-check">
                  <input v-model="selected[n.id]" type="checkbox" :aria-label="'Select ' + n.remarks" />
                </td>
                <td>
                  {{ n.remarks }}
                  <span v-if="n.id === current" class="pw-tag">In use</span>
                </td>
                <td class="pw-muted">{{ typeLabel(n) }}</td>
                <td class="pw-muted" :title="n.special ? '' : n.address + ':' + n.port">{{ n.special ? '—' : n.address + ':' + n.port }}</td>
                <td class="pw-num" :class="latencyClass(result(n).ping)">{{ latencyText(result(n), 'ping') }}</td>
                <td class="pw-num" :class="latencyClass(result(n).url)">{{ latencyText(result(n), 'url') }}</td>
                <td class="pw-actions">
                  <button type="button" class="pw-btn pw-btn-sm" :disabled="busy || n.id === current" @click="use(n)">Use</button>
                  <button type="button" class="pw-btn pw-btn-sm" :disabled="result(n).testing" @click="test(n, 'url')">Test</button>
                  <button type="button" class="pw-btn pw-btn-sm pw-btn-danger" :disabled="busy" @click="remove([n.id])">Delete</button>
                </td>
              </tr>
            </tbody>
          </table>
        </div>
      </div>
    </section>
  </div>
</template>

<script>
import { rpc } from '../rpc.js'

const PROTOCOLS = {
  vless: 'VLESS', vmess: 'VMess', trojan: 'Trojan', shadowsocks: 'SS', socks: 'SOCKS', http: 'HTTP',
  wireguard: 'WG', hysteria2: 'HY2', _shunt: 'Shunt', _balancing: 'Balancer', _urltest: 'URLTest', _iface: 'Interface',
}

// GL's RPC server handles one request at a time, so tests run two at a time.
const TEST_CONCURRENCY = 2

export default {
  name: 'NodesView',
  data() {
    return {
      nodes: [],
      current: null,
      loaded: false,
      filter: '',
      selected: {},
      results: {},
      adding: false,
      links: '',
      group: '',
      busy: false,
      testing: false,
      error: '',
    }
  },
  computed: {
    visible() {
      const q = this.filter.toLowerCase()
      if (!q) return this.nodes
      return this.nodes.filter((n) =>
        [n.remarks, n.address, n.group, n.protocol].some((v) => v && String(v).toLowerCase().includes(q)),
      )
    },
    groups() {
      const out = {}
      for (const n of this.visible) {
        const name = n.group || 'Default'
        ;(out[name] = out[name] || []).push(n)
      }
      return Object.keys(out).map((name) => ({ name, nodes: out[name] }))
    },
    selectedIds() {
      return this.nodes.filter((n) => this.selected[n.id]).map((n) => n.id)
    },
  },
  activated() {
    this.load()
  },
  methods: {
    fail(e) {
      this.error = e.message || String(e)
    },
    load() {
      return rpc('list_nodes')
        .then((r) => {
          this.nodes = r.nodes || []
          this.current = r.current || null
          this.loaded = true
          const keep = {}
          for (const n of this.nodes) if (this.selected[n.id]) keep[n.id] = true
          this.selected = keep
        })
        .catch(this.fail)
    },
    typeLabel(n) {
      return PROTOCOLS[n.protocol] || n.protocol || n.type || ''
    },
    result(n) {
      return this.results[n.id] || {}
    },
    setResult(id, patch) {
      this.$set(this.results, id, { ...(this.results[id] || {}), ...patch })
    },
    latencyText(r, kind) {
      if (r.testing === kind) return '…'
      const v = r[kind]
      if (v === undefined) return '—'
      return v === null ? 'Timeout' : v + ' ms'
    },
    latencyClass(v) {
      if (v === undefined) return 'pw-muted'
      if (v === null) return 'pw-bad'
      return v < 300 ? 'pw-ok' : 'pw-warn'
    },
    test(n, kind) {
      if (n.special && kind === 'ping') return Promise.resolve()
      this.setResult(n.id, { testing: kind })
      const call =
        kind === 'ping'
          ? rpc('ping_node', { id: n.id }).then((r) => (r && r.ping != null ? Math.round(r.ping) : null))
          : rpc('urltest_node', { id: n.id }).then((r) => (r && r.use_time ? Math.round(Number(r.use_time)) : null))
      return call
        .catch(() => null)
        .then((v) => this.setResult(n.id, { [kind]: v, testing: false }))
    },
    testAll(kind) {
      const queue = this.visible.slice()
      this.testing = true
      const worker = () => {
        const n = queue.shift()
        return n ? this.test(n, kind).then(worker) : Promise.resolve()
      }
      const workers = []
      for (let i = 0; i < TEST_CONCURRENCY; i++) workers.push(worker())
      Promise.all(workers).finally(() => (this.testing = false))
    },
    allSelected(g) {
      return g.nodes.length > 0 && g.nodes.every((n) => this.selected[n.id])
    },
    selectGroup(g, on) {
      for (const n of g.nodes) this.$set(this.selected, n.id, on)
    },
    use(n) {
      this.busy = true
      rpc('set_node', { id: n.id })
        .then(() => (this.current = n.id))
        .catch(this.fail)
        .finally(() => (this.busy = false))
    },
    remove(ids) {
      const names = this.nodes.filter((n) => ids.includes(n.id)).map((n) => n.remarks)
      const what = ids.length === 1 ? `"${names[0]}"` : `${ids.length} nodes`
      if (!window.confirm(`Delete ${what}? This cannot be undone.`)) return
      this.busy = true
      rpc('delete_nodes', { ids })
        .then(this.load)
        .catch(this.fail)
        .finally(() => (this.busy = false))
    },
    removeSelected() {
      this.remove(this.selectedIds)
    },
    addLinks() {
      this.busy = true
      this.error = ''
      rpc('add_links', { links: this.links, group: this.group })
        .then(() => {
          this.links = ''
          this.adding = false
          return this.load()
        })
        .catch(this.fail)
        .finally(() => (this.busy = false))
    },
  },
}
</script>

<style>
.pw-toolbar {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  margin-top: 8px;
}
.pw-card > .pw-toolbar:first-child {
  margin-top: 0;
  margin-bottom: 12px;
}
.pw-spacer {
  flex: 1;
}
.pw-empty {
  margin: 16px 0 4px;
}
.pw-group {
  margin-top: 16px;
}
.pw-group-name {
  font-weight: 600;
  margin-bottom: 6px;
}
.pw-table-wrap {
  overflow-x: auto;
}
/* Fixed layout keeps columns aligned across the per-group tables. */
.pw-table {
  width: 100%;
  min-width: 760px;
  table-layout: fixed;
  border-collapse: collapse;
}
.pw-table th,
.pw-table td {
  text-align: left;
  padding: 8px;
  border-top: 1px solid var(--pw-border);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
.pw-col-type {
  width: 80px;
}
.pw-col-addr {
  width: 200px;
}
.pw-col-ms {
  width: 84px;
}
.pw-col-actions {
  width: 176px;
}
.pw-table th {
  color: var(--pw-muted);
  font-weight: 500;
  font-size: 12px;
  border-top: 0;
}
.pw-table tr.is-current td {
  background: var(--pw-primary-soft);
}
.pw-col-check {
  width: 28px;
}
.pw-num {
  text-align: right !important;
  font-variant-numeric: tabular-nums;
}
.pw-actions {
  text-align: right !important;
}
.pw-actions .pw-btn + .pw-btn {
  margin-left: 4px;
}
.pw-tag {
  display: inline-block;
  margin-left: 6px;
  padding: 0 6px;
  border-radius: 4px;
  font-size: 11px;
  background: var(--pw-primary);
  color: #fff;
}
</style>
