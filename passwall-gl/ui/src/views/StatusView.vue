<template>
  <div>
    <div v-if="error" class="pw-error">{{ error }}</div>

    <section class="pw-card">
      <h3 class="pw-card-title">
        <span>PassWall</span>
        <label class="pw-switch" title="Main switch">
          <input type="checkbox" :checked="status.enabled" :disabled="busy" @change="setEnabled($event.target.checked)" />
          <span></span>
        </label>
      </h3>
      <div class="pw-row">
        <div class="pw-row-label">Running status</div>
        <div class="pw-status">
          <span><i :class="['pw-dot', dot(status.tcp_status)]"></i>TCP</span>
          <span><i :class="['pw-dot', dot(status.udp_status)]"></i>UDP</span>
          <span><i :class="['pw-dot', dot(status.dns_mode_status)]"></i>DNS</span>
        </div>
      </div>
      <div class="pw-row">
        <div class="pw-row-label">
          Node
          <div v-if="status.node_remark" class="pw-row-help">{{ status.node_remark }}</div>
        </div>
        <!-- :selected on each option, not :value on the select: the options can
             arrive after the value, and the select would keep the first one. -->
        <select class="pw-select" :disabled="busy || !nodes.length" @change="setNode($event.target.value)">
          <option value="" disabled :selected="!status.node">{{ nodes.length ? 'Choose a node' : 'No nodes yet' }}</option>
          <optgroup v-for="g in groupedNodes" :key="g.name" :label="g.name">
            <option v-for="n in g.nodes" :key="n.id" :value="n.id" :selected="n.id === status.node">{{ nodeLabel(n) }}</option>
          </optgroup>
        </select>
      </div>
      <div class="pw-row">
        <div class="pw-row-label">Versions</div>
        <div class="pw-muted">PassWall {{ status.version || '—' }} · Xray {{ status.xray_version || 'not installed' }}</div>
      </div>
    </section>

    <section class="pw-card">
      <h3 class="pw-card-title">
        <span>Connectivity</span>
        <button type="button" class="pw-btn pw-btn-sm" :disabled="probing" @click="probeAll">Test all</button>
      </h3>
      <div class="pw-probes">
        <button v-for="p in probes" :key="p.id" type="button" class="pw-probe" :disabled="p.testing" @click="probe(p)">
          <span class="pw-probe-name">{{ p.label }}</span>
          <span :class="probeClass(p)">{{ probeText(p) }}</span>
        </button>
      </div>
    </section>

    <section class="pw-card">
      <h3 class="pw-card-title">
        <span>Proxy settings</span>
        <button type="button" class="pw-btn pw-btn-primary pw-btn-sm" :disabled="busy || !dirty" @click="saveSettings">Save &amp; apply</button>
      </h3>
      <div class="pw-row">
        <div class="pw-row-label">TCP default proxy mode</div>
        <select v-model="form.tcp_proxy_mode" class="pw-select">
          <option value="proxy">Proxy</option>
          <option value="disable">No proxy</option>
        </select>
      </div>
      <div class="pw-row">
        <div class="pw-row-label">UDP default proxy mode</div>
        <select v-model="form.udp_proxy_mode" class="pw-select">
          <option value="proxy">Proxy</option>
          <option value="disable">No proxy</option>
        </select>
      </div>
      <div class="pw-row">
        <div class="pw-row-label">China list</div>
        <select v-model="form.chn_list" class="pw-select">
          <option value="0">Not used</option>
          <option value="direct">Direct connection</option>
          <option value="proxy">Proxy</option>
        </select>
      </div>
      <div v-for="f in flags" :key="f.key" class="pw-row">
        <div class="pw-row-label">
          {{ f.label }}
          <div v-if="f.help" class="pw-row-help">{{ f.help }}</div>
        </div>
        <label class="pw-switch">
          <input v-model="form[f.key]" type="checkbox" true-value="1" false-value="0" />
          <span></span>
        </label>
      </div>
    </section>
  </div>
</template>

<script>
import { rpc, asList } from '../rpc.js'
import { nodeLabel } from '../labels.js'

// PassWall's defaults for options that are unset in UCI.
const DEFAULTS = {
  tcp_proxy_mode: 'proxy',
  udp_proxy_mode: 'proxy',
  chn_list: 'direct',
  localhost_proxy: '1',
  client_proxy: '1',
  use_direct_list: '1',
  use_proxy_list: '1',
  use_block_list: '1',
  use_gfw_list: '1',
}

export default {
  name: 'StatusView',
  data() {
    return {
      status: {},
      nodes: [],
      saved: {},
      form: { ...DEFAULTS },
      busy: false,
      probing: false,
      error: '',
      timer: null,
      flags: [
        { key: 'localhost_proxy', label: 'Localhost proxy', help: 'Proxy traffic from the router itself.' },
        { key: 'client_proxy', label: 'Client proxy', help: 'Proxy devices on the LAN. Access control can still pick devices when off.' },
        { key: 'use_direct_list', label: 'Use direct list' },
        { key: 'use_proxy_list', label: 'Use proxy list' },
        { key: 'use_block_list', label: 'Use block list' },
        { key: 'use_gfw_list', label: 'Use GFW list' },
      ],
      probes: [
        { id: 'aliyun', label: 'Aliyun' },
        { id: 'google', label: 'Google' },
        { id: 'github', label: 'GitHub' },
        { id: 'youtube', label: 'YouTube' },
      ].map((p) => ({ ...p, testing: false, ms: null, failed: false })),
    }
  },
  computed: {
    groupedNodes() {
      const groups = {}
      for (const n of this.nodes) {
        const name = n.group || 'Default'
        ;(groups[name] = groups[name] || []).push(n)
      }
      return Object.keys(groups).map((name) => ({ name, nodes: groups[name] }))
    },
    dirty() {
      return Object.keys(DEFAULTS).some((k) => this.form[k] !== this.saved[k])
    },
  },
  activated() {
    this.load()
    this.timer = setInterval(this.refreshStatus, 5000)
  },
  deactivated() {
    clearInterval(this.timer)
  },
  beforeDestroy() {
    clearInterval(this.timer)
  },
  methods: {
    nodeLabel,
    // Red only means "should be running but isn't"; while off, stay neutral.
    dot(v) {
      if (!this.status.enabled) return ''
      if (v === true) return 'is-ok'
      if (v === false) return 'is-bad'
      return ''
    },
    fail(e) {
      this.error = e.message || String(e)
    },
    load() {
      this.error = ''
      Promise.all([rpc('get_status'), rpc('get_nodes'), rpc('get_global')])
        .then(([status, list, global]) => {
          this.status = status
          this.nodes = asList(list.nodes)
          const values = {}
          for (const k of Object.keys(DEFAULTS)) values[k] = global[k] != null ? global[k] : DEFAULTS[k]
          this.saved = values
          this.form = { ...values }
        })
        .catch(this.fail)
    },
    refreshStatus() {
      rpc('get_status')
        .then((s) => (this.status = s))
        .catch(() => {})
    },
    setEnabled(on) {
      this.busy = true
      rpc('set_global', { values: { enabled: on } })
        .then(() => {
          this.status = { ...this.status, enabled: on }
          setTimeout(this.refreshStatus, 3000)
        })
        .catch(this.fail)
        .finally(() => (this.busy = false))
    },
    setNode(id) {
      this.busy = true
      rpc('set_node', { id })
        .then(() => {
          this.status = { ...this.status, node: id }
          setTimeout(this.refreshStatus, 3000)
        })
        .catch(this.fail)
        .finally(() => (this.busy = false))
    },
    saveSettings() {
      const values = {}
      for (const k of Object.keys(DEFAULTS)) {
        if (this.form[k] !== this.saved[k]) values[k] = this.form[k]
      }
      this.busy = true
      rpc('set_global', { values })
        .then(() => {
          this.saved = { ...this.form }
          setTimeout(this.refreshStatus, 3000)
        })
        .catch(this.fail)
        .finally(() => (this.busy = false))
    },
    probe(p) {
      p.testing = true
      p.failed = false
      return rpc('connect_status', { target: p.id })
        .then((r) => {
          p.ms = r && r.use_time ? Math.round(Number(r.use_time)) : null
          p.failed = p.ms === null
        })
        .catch(() => (p.failed = true))
        .finally(() => (p.testing = false))
    },
    probeAll() {
      this.probing = true
      Promise.all(this.probes.map(this.probe)).finally(() => (this.probing = false))
    },
    probeText(p) {
      if (p.testing) return 'Testing…'
      if (p.failed) return 'Failed'
      if (p.ms !== null) return p.ms + ' ms'
      return 'Not tested'
    },
    probeClass(p) {
      if (p.failed) return 'pw-bad'
      if (p.ms !== null) return p.ms < 300 ? 'pw-ok' : 'pw-warn'
      return 'pw-muted'
    },
  },
}
</script>

<style>
.pw-status {
  display: flex;
  gap: 16px;
}
.pw-probes {
  display: grid;
  grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
  gap: 10px;
}
.pw-probe {
  display: flex;
  flex-direction: column;
  align-items: flex-start;
  gap: 2px;
  border: 1px solid var(--pw-border);
  border-radius: 8px;
  background: #fff;
  padding: 10px 12px;
  font: inherit;
  cursor: pointer;
  text-align: left;
}
.pw-probe:hover:not(:disabled) {
  border-color: var(--pw-primary);
}
.pw-probe-name {
  font-weight: 600;
}
</style>
