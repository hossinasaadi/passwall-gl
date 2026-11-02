<template>
  <div>
    <div v-if="error" class="pw-error">{{ error }}</div>
    <div v-if="notice" class="pw-notice">{{ notice }}</div>

    <section v-if="editing" class="pw-card">
      <h3 class="pw-card-title">
        <span>{{ editing.id ? 'Edit subscription' : 'Add subscription' }}</span>
      </h3>
      <div class="pw-field">
        <label for="pw-sub-remark">Name</label>
        <input id="pw-sub-remark" v-model="editing.values.remark" class="pw-input pw-wide" maxlength="64" placeholder="My provider" />
        <div class="pw-row-help">Its nodes appear in Node List under this name.</div>
      </div>
      <div class="pw-field">
        <label for="pw-sub-url">Subscription URL</label>
        <textarea id="pw-sub-url" v-model.trim="editing.values.url" class="pw-textarea pw-short" spellcheck="false" placeholder="https://…"></textarea>
      </div>
      <div class="pw-row">
        <div class="pw-row-label">Update automatically</div>
        <span class="pw-inline">
          <select v-model="editing.values.update_week_mode" class="pw-select pw-narrow">
            <option v-for="o in weekModes" :key="o.value" :value="o.value">{{ o.label }}</option>
          </select>
          <select v-if="editing.values.update_week_mode === '8'" v-model="editing.values.update_interval_mode" class="pw-select pw-narrow" aria-label="Interval">
            <option v-for="h in 24" :key="h" :value="String(h)">every {{ h }} h</option>
          </select>
          <select v-else-if="editing.values.update_week_mode !== ''" v-model="editing.values.update_time_mode" class="pw-select pw-narrow" aria-label="Time">
            <option v-for="h in 24" :key="h" :value="h - 1 + ':00'">at {{ h - 1 }}:00</option>
          </select>
        </span>
      </div>
      <div class="pw-row">
        <div class="pw-row-label">Update when the router starts</div>
        <label class="pw-switch">
          <input v-model="editing.values.boot_update" type="checkbox" true-value="1" false-value="0" />
          <span></span>
        </label>
      </div>

      <details class="pw-details">
        <summary>Advanced</summary>
        <div class="pw-row">
          <div class="pw-row-label">User-Agent<div class="pw-row-help">Some providers return different formats per app.</div></div>
          <select v-model="uaPreset" class="pw-select">
            <option v-for="u in userAgents" :key="u.value" :value="u.value">{{ u.label }}</option>
            <option value="custom">Custom…</option>
          </select>
        </div>
        <div v-if="uaPreset === 'custom'" class="pw-field">
          <input v-model="editing.values.user_agent" class="pw-input pw-wide" maxlength="512" aria-label="Custom User-Agent" />
        </div>
        <div class="pw-row">
          <div class="pw-row-label">Fetch the subscription</div>
          <select v-model="editing.values.access_mode" class="pw-select">
            <option value="">Automatically</option>
            <option value="direct">Directly</option>
            <option value="proxy">Through the proxy</option>
          </select>
        </div>
        <div class="pw-row">
          <div class="pw-row-label">Domain strategy</div>
          <select v-model="editing.values.domain_strategy" class="pw-select">
            <option value="">Auto</option>
            <option value="UseIPv4v6">Prefer IPv4</option>
            <option value="UseIPv6v4">Prefer IPv6</option>
            <option value="UseIPv4">IPv4 only</option>
            <option value="UseIPv6">IPv6 only</option>
          </select>
        </div>
        <div class="pw-row">
          <div class="pw-row-label">
            Skip certificate checks
            <div class="pw-row-help">Only for nodes whose link doesn't say. Makes those connections easier to intercept.</div>
          </div>
          <label class="pw-switch">
            <input v-model="editing.values.allowInsecure" type="checkbox" true-value="1" false-value="0" />
            <span></span>
          </label>
        </div>
        <div class="pw-row">
          <div class="pw-row-label">Filter nodes by name</div>
          <select v-model="editing.values.filter_keyword_mode" class="pw-select">
            <option value="5">Use the global filter</option>
            <option v-for="m in filterModes" :key="m.value" :value="m.value">{{ m.label }}</option>
          </select>
        </div>
        <filter-lists v-if="['1', '2', '3', '4'].includes(editing.values.filter_keyword_mode)" :mode="editing.values.filter_keyword_mode" :lists="editing.lists" />
      </details>

      <div class="pw-toolbar pw-actions-end">
        <button type="button" class="pw-btn" @click="editing = null">Cancel</button>
        <button type="button" class="pw-btn pw-btn-primary" :disabled="busy" @click="save">Save</button>
      </div>
    </section>

    <section class="pw-card">
      <h3 class="pw-card-title">
        <span>Subscriptions</span>
        <span class="pw-inline">
          <button type="button" class="pw-btn pw-btn-sm" :disabled="busy || updating || !subs.length" @click="updateAll">Update all</button>
          <button type="button" class="pw-btn pw-btn-primary pw-btn-sm" :disabled="!!editing" @click="startAdd">Add subscription</button>
        </span>
      </h3>
      <p v-if="updating" class="pw-updating">Updating subscriptions… new nodes appear when it finishes.</p>
      <p v-if="loaded && !subs.length" class="pw-muted pw-empty">
        No subscriptions yet. Add your provider's subscription URL to import its nodes and keep them up to date.
      </p>
      <div v-for="s in subs" :key="s.id" class="pw-sub">
        <div class="pw-sub-main">
          <div class="pw-sub-name">{{ s.remark || '(no name)' }}</div>
          <div class="pw-row-help">
            {{ s.nodes }} {{ s.nodes === 1 ? 'node' : 'nodes' }} · {{ hostOf(s.url) }} · {{ scheduleText(s) }}
            <span v-if="s.rem_traffic || s.expired_date"> · {{ [s.rem_traffic, s.expired_date].filter(Boolean).join(' / ') }}</span>
          </div>
        </div>
        <div class="pw-sub-actions">
          <button type="button" class="pw-btn pw-btn-sm" :disabled="busy || updating" @click="update(s)">Update</button>
          <button type="button" class="pw-btn pw-btn-sm" :disabled="!!editing" @click="startEdit(s)">Edit</button>
          <button type="button" class="pw-btn pw-btn-sm pw-btn-danger" :disabled="busy || !s.nodes" @click="deleteNodes(s)">Delete nodes</button>
          <button type="button" class="pw-btn pw-btn-sm pw-btn-danger" :disabled="busy" @click="remove(s)">Delete</button>
        </div>
      </div>
    </section>

    <section class="pw-card">
      <details class="pw-details" :open="filterOpen" @toggle="filterOpen = $event.target.open">
        <summary class="pw-card-title">Global name filter</summary>
        <p class="pw-row-help">
          Applies to subscriptions set to "Use the global filter". Providers often add fake entries such as
          remaining traffic or an expiry date; matching names are dropped.
        </p>
        <div class="pw-row">
          <div class="pw-row-label">Mode</div>
          <select v-model="filter.filter_keyword_mode" class="pw-select">
            <option v-for="m in filterModes" :key="m.value" :value="m.value">{{ m.label }}</option>
          </select>
        </div>
        <filter-lists v-if="filter.filter_keyword_mode !== '0'" :mode="filter.filter_keyword_mode" :lists="filterLists" />
        <div class="pw-toolbar pw-actions-end">
          <button type="button" class="pw-btn pw-btn-danger" :disabled="busy" @click="deleteAllNodes">Delete all subscription nodes</button>
          <button type="button" class="pw-btn pw-btn-primary" :disabled="busy" @click="saveFilter">Save filter</button>
        </div>
      </details>
    </section>
  </div>
</template>

<script>
import { rpc, asList } from '../rpc.js'

// One keyword per line in the page; a list in UCI.
const toText = (list) => asList(list).join('\n')
const toList = (text) => text.split('\n').map((s) => s.trim()).filter(Boolean)

const FilterLists = {
  props: { mode: String, lists: Object },
  render(h) {
    const box = (key, label, help) =>
      h('div', { staticClass: 'pw-field' }, [
        h('label', label),
        h('textarea', {
          staticClass: 'pw-textarea pw-short',
          attrs: { spellcheck: 'false', placeholder: 'One word or phrase per line' },
          domProps: { value: this.lists[key] },
          on: { input: (e) => (this.lists[key] = e.target.value) },
        }),
        h('div', { staticClass: 'pw-row-help' }, help),
      ])
    const out = []
    if (this.mode !== '2') out.push(box('discard', 'Drop nodes whose name contains', 'Matched as plain text.'))
    if (this.mode !== '1') out.push(box('keep', 'Keep only nodes whose name contains', 'Matched as plain text.'))
    return h('div', out)
  },
}

const USER_AGENTS = [
  { value: 'passwall', label: 'PassWall' },
  { value: 'v2rayN/9.99', label: 'v2rayN' },
  { value: 'clash.meta/v9.99.99', label: 'Clash.Meta' },
  { value: 'Shadowrocket/9999 CFNetwork/3896.100.1.2.1 Darwin/27.0.0 iPhone19,7', label: 'Shadowrocket' },
  { value: 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36 Edg/122.0.0.0', label: 'Edge for Linux' },
  { value: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/122.0.0.0 Safari/537.36 Edg/122.0.0.0', label: 'Edge for Windows' },
]

const WEEKDAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']

const NEW_SUBSCRIPTION = {
  remark: '',
  url: '',
  update_week_mode: '',
  update_time_mode: '0:00',
  update_interval_mode: '2',
  boot_update: '0',
  filter_keyword_mode: '5',
  user_agent: 'passwall',
  access_mode: '',
  domain_strategy: '',
  allowInsecure: '0',
}

export default {
  name: 'SubscriptionsView',
  components: { FilterLists },
  data() {
    return {
      subs: [],
      filter: { filter_keyword_mode: '0' },
      filterLists: { discard: '', keep: '' },
      filterOpen: false,
      updating: false,
      loaded: false,
      editing: null,
      uaPreset: 'passwall',
      busy: false,
      error: '',
      notice: '',
      timer: null,
      countBefore: 0,
      userAgents: USER_AGENTS,
      weekModes: [
        { value: '', label: 'Off' },
        { value: '8', label: 'Repeatedly' },
        { value: '7', label: 'Every day' },
        ...[1, 2, 3, 4, 5, 6, 0].map((d) => ({ value: String(d), label: 'Every ' + WEEKDAYS[d] })),
      ],
      filterModes: [
        { value: '0', label: 'Off' },
        { value: '1', label: 'Drop matching names' },
        { value: '2', label: 'Keep only matching names' },
        { value: '3', label: 'Drop matching, but the keep list wins' },
        { value: '4', label: 'Keep matching, but the drop list wins' },
      ],
    }
  },
  activated() {
    this.load()
  },
  deactivated() {
    clearInterval(this.timer)
    this.timer = null
  },
  beforeDestroy() {
    clearInterval(this.timer)
  },
  methods: {
    fail(e) {
      this.notice = ''
      this.error = e.message || String(e)
    },
    load() {
      return rpc('get_subscriptions')
        .then((r) => {
          this.subs = asList(r.subscriptions)
          this.updating = !!r.updating
          this.loaded = true
          if (!this.filterOpen) {
            this.filter = { filter_keyword_mode: (r.filter && r.filter.filter_keyword_mode) || '0' }
            this.filterLists = { discard: toText(r.filter && r.filter.filter_discard_list), keep: toText(r.filter && r.filter.filter_keep_list) }
          }
          this.watchUpdates()
        })
        .catch(this.fail)
    },
    totalNodes() {
      return this.subs.reduce((n, s) => n + (s.nodes || 0), 0)
    },
    // While PassWall's subscribe script runs, refresh until it finishes, then
    // say what changed. The script reports failures only in its log.
    watchUpdates() {
      if (this.updating && !this.timer) {
        this.timer = setInterval(this.load, 3000)
      } else if (!this.updating && this.timer) {
        clearInterval(this.timer)
        this.timer = null
        const diff = this.totalNodes() - (this.countBefore || 0)
        if (diff !== 0) {
          const n = Math.abs(diff) === 1 ? 'node' : 'nodes'
          this.notice = `Update finished: ${diff > 0 ? '+' : ''}${diff} ${n}. They are in Node List.`
        } else {
          this.notice = 'Update finished with no change in nodes. If you expected new ones, Runtime Logs shows what the provider returned.'
        }
      }
    },
    hostOf(url) {
      const m = /^https?:\/\/([^/?#]+)/.exec(url || '')
      return m ? m[1] : 'no URL'
    },
    scheduleText(s) {
      const w = s.update_week_mode
      if (!w) return 'manual updates'
      if (w === '8') return `updates every ${s.update_interval_mode || 2} h`
      const at = s.update_time_mode || '0:00'
      return w === '7' ? `updates daily at ${at}` : `updates ${WEEKDAYS[Number(w)]}s at ${at}`
    },
    startAdd() {
      this.error = this.notice = ''
      this.editing = { id: null, values: { ...NEW_SUBSCRIPTION }, lists: { discard: '', keep: '' } }
      this.uaPreset = 'passwall'
    },
    startEdit(s) {
      this.error = this.notice = ''
      const values = {}
      for (const k of Object.keys(NEW_SUBSCRIPTION)) values[k] = s[k] != null ? String(s[k]) : NEW_SUBSCRIPTION[k]
      this.editing = { id: s.id, values, lists: { discard: toText(s.filter_discard_list), keep: toText(s.filter_keep_list) } }
      this.uaPreset = USER_AGENTS.some((u) => u.value === values.user_agent) ? values.user_agent : 'custom'
    },
    save() {
      const { id, values, lists } = this.editing
      const out = { ...values, filter_discard_list: toList(lists.discard), filter_keep_list: toList(lists.keep) }
      if (this.uaPreset !== 'custom') out.user_agent = this.uaPreset
      this.busy = true
      this.error = ''
      rpc('save_subscription', { id, values: out })
        .then((r) => {
          this.editing = null
          // A new subscription has no nodes yet, so fetch them right away.
          if (!id) return this.load().then(() => this.update({ id: r.id }))
          return this.load().then(() => (this.notice = 'Saved.'))
        })
        .catch(this.fail)
        .finally(() => (this.busy = false))
    },
    startUpdate(method, args) {
      this.error = this.notice = ''
      this.countBefore = this.totalNodes()
      return rpc(method, args)
        .then(() => {
          this.updating = true
          this.watchUpdates()
        })
        .catch(this.fail)
    },
    update(s) {
      return this.startUpdate('update_subscription', { id: s.id })
    },
    updateAll() {
      return this.startUpdate('update_all_subscriptions')
    },
    confirmThen(message, method, args, done) {
      if (!window.confirm(message)) return
      this.busy = true
      this.error = this.notice = ''
      rpc(method, args)
        .then(() => {
          this.notice = done
          return this.load()
        })
        .catch(this.fail)
        .finally(() => (this.busy = false))
    },
    deleteNodes(s) {
      this.confirmThen(`Delete the ${s.nodes} nodes from "${s.remark}"? The subscription stays.`,
        'delete_subscription_nodes', { id: s.id }, 'Nodes deleted.')
    },
    remove(s) {
      this.confirmThen(`Delete the subscription "${s.remark}" and its ${s.nodes} nodes?`,
        'delete_subscription', { id: s.id }, 'Subscription deleted.')
    },
    deleteAllNodes() {
      this.confirmThen('Delete every node that came from a subscription? Nodes you added by hand stay.',
        'delete_all_subscription_nodes', {}, 'All subscription nodes deleted.')
    },
    saveFilter() {
      this.busy = true
      this.error = this.notice = ''
      const values = {
        filter_keyword_mode: this.filter.filter_keyword_mode,
        filter_discard_list: toList(this.filterLists.discard),
        filter_keep_list: toList(this.filterLists.keep),
      }
      rpc('set_subscribe_filter', { values })
        .then(() => (this.notice = 'Filter saved. It applies from the next update.'))
        .catch(this.fail)
        .finally(() => (this.busy = false))
    },
  },
}
</script>

<style>
.pw-field {
  margin: 10px 0;
}
.pw-field > label {
  display: block;
  font-weight: 500;
  margin-bottom: 4px;
}
.pw-wide {
  width: 100%;
}
.pw-textarea.pw-short {
  min-height: 64px;
}
.pw-inline {
  display: inline-flex;
  flex-wrap: wrap;
  gap: 8px;
  align-items: center;
  font-weight: 400;
}
.pw-select.pw-narrow {
  min-width: 0;
  width: auto;
}
.pw-actions-end {
  justify-content: flex-end;
  margin-top: 12px;
}
.pw-details > summary {
  cursor: pointer;
  color: var(--pw-primary);
  margin: 8px 0;
  list-style-position: inside;
}
.pw-details > summary.pw-card-title {
  display: list-item;
  color: inherit;
  margin: 0;
}
.pw-updating {
  color: var(--pw-warn);
  margin: 0 0 8px;
}
.pw-sub {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  justify-content: space-between;
  gap: 8px 16px;
  padding: 10px 0;
  border-top: 1px solid var(--pw-border);
}
.pw-sub:first-of-type {
  border-top: 0;
}
.pw-sub-main {
  min-width: 0;
}
.pw-sub-name {
  font-weight: 600;
}
.pw-sub-actions {
  display: flex;
  flex-wrap: wrap;
  gap: 4px;
}
</style>
