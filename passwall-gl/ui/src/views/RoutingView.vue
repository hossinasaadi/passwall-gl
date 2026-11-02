<template>
  <div>
    <div v-if="error" class="pw-error">{{ error }}</div>
    <div v-if="notice" class="pw-notice">{{ notice }}</div>

    <section class="pw-card">
      <div class="pw-segments" role="tablist">
        <button
          v-for="c in categories"
          :key="c.id"
          type="button"
          role="tab"
          :aria-selected="current === c.id"
          :class="['pw-segment', { 'is-active': current === c.id }]"
          @click="current = c.id"
        >
          {{ c.label }}<span v-if="countOf(c)" class="pw-count">{{ countOf(c) }}</span>
        </button>
      </div>

      <template v-for="c in categories">
        <div v-if="current === c.id" :key="c.id">
          <div class="pw-row">
            <div class="pw-row-label">
              Use the {{ c.label.toLowerCase() }} list
              <div class="pw-row-help">{{ c.help }}</div>
            </div>
            <label class="pw-switch">
              <input v-model="flags[c.flag]" type="checkbox" true-value="1" false-value="0" />
              <span></span>
            </label>
          </div>
          <div class="pw-field">
            <label :for="'pw-' + c.id + '-host'">Domains</label>
            <textarea
              :id="'pw-' + c.id + '-host'"
              v-model="lists[c.id + '_host']"
              class="pw-textarea pw-rules"
              spellcheck="false"
              wrap="off"
              :placeholder="'example.com\n# a comment\ngeosite:' + c.geosite"
            ></textarea>
            <div class="pw-row-help">One per line. A domain covers its subdomains. geosite: entries use Xray's geo data.</div>
          </div>
          <div class="pw-field">
            <label :for="'pw-' + c.id + '-ip'">IP addresses and ranges</label>
            <textarea
              :id="'pw-' + c.id + '-ip'"
              v-model="lists[c.id + '_ip']"
              class="pw-textarea pw-rules"
              spellcheck="false"
              wrap="off"
              :placeholder="'203.0.113.7\n198.51.100.0/24\ngeoip:' + c.geoip"
            ></textarea>
            <div class="pw-row-help">One per line: an address, a range like 10.0.0.0/8, or geoip: entries.</div>
          </div>
        </div>
      </template>

      <div class="pw-toolbar pw-actions-end">
        <span v-if="dirty" class="pw-muted">Unsaved changes</span>
        <button type="button" class="pw-btn" :disabled="busy || !dirty" @click="load">Discard</button>
        <button type="button" class="pw-btn pw-btn-primary" :disabled="busy || !dirty" @click="save">Save &amp; apply</button>
      </div>
    </section>
  </div>
</template>

<script>
import { rpc } from '../rpc.js'

const LIST_NAMES = ['direct_host', 'direct_ip', 'proxy_host', 'proxy_ip', 'block_host', 'block_ip']
const FLAG_NAMES = ['use_direct_list', 'use_proxy_list', 'use_block_list']

const entries = (text) => (text || '').split('\n').filter((l) => l.trim() && !l.trim().startsWith('#')).length

export default {
  name: 'RoutingView',
  data() {
    return {
      current: 'direct',
      lists: Object.fromEntries(LIST_NAMES.map((n) => [n, ''])),
      flags: Object.fromEntries(FLAG_NAMES.map((n) => [n, '1'])),
      saved: null,
      busy: false,
      error: '',
      notice: '',
      categories: [
        { id: 'direct', label: 'Direct', flag: 'use_direct_list', geosite: 'category-ir', geoip: 'ir',
          help: 'Sites and addresses here never go through the proxy.' },
        { id: 'proxy', label: 'Proxy', flag: 'use_proxy_list', geosite: 'youtube', geoip: 'telegram',
          help: 'Sites and addresses here always go through the proxy.' },
        { id: 'block', label: 'Block', flag: 'use_block_list', geosite: 'category-ads-all', geoip: 'private',
          help: 'Connections to these are refused.' },
      ],
    }
  },
  computed: {
    snapshot() {
      return JSON.stringify([this.lists, this.flags])
    },
    dirty() {
      return this.saved !== null && this.snapshot !== this.saved
    },
  },
  activated() {
    if (!this.dirty) this.load()
  },
  methods: {
    fail(e) {
      this.notice = ''
      this.error = e.message || String(e)
    },
    countOf(c) {
      return entries(this.lists[c.id + '_host']) + entries(this.lists[c.id + '_ip'])
    },
    load() {
      this.error = this.notice = ''
      return Promise.all([rpc('get_rules'), rpc('get_global')])
        .then(([rules, global]) => {
          for (const n of LIST_NAMES) this.lists[n] = (rules.lists && rules.lists[n]) || ''
          for (const n of FLAG_NAMES) this.flags[n] = global[n] != null ? global[n] : '1'
          this.saved = this.snapshot
        })
        .catch(this.fail)
    },
    save() {
      const before = JSON.parse(this.saved)
      const lists = {}
      for (const n of LIST_NAMES) if (this.lists[n] !== before[0][n]) lists[n] = this.lists[n]
      const flags = {}
      for (const n of FLAG_NAMES) if (this.flags[n] !== before[1][n]) flags[n] = this.flags[n]
      this.busy = true
      this.error = this.notice = ''
      // Each call restarts PassWall, so when both changed the switches are
      // saved without a restart and the lists' restart applies them too.
      const listsChanged = Object.keys(lists).length > 0
      const steps = []
      if (Object.keys(flags).length) steps.push(() => rpc('set_global', { values: flags, apply: !listsChanged }))
      if (listsChanged) steps.push(() => rpc('save_rules', { lists }))
      steps
        .reduce((p, step) => p.then(step), Promise.resolve())
        .then(() => this.load())
        .then(() => (this.notice = 'Saved. If PassWall is on, it takes a few seconds to apply.'))
        .catch(this.fail)
        .finally(() => (this.busy = false))
    },
  },
}
</script>

<style>
.pw-segments {
  display: inline-flex;
  border: 1px solid var(--pw-border);
  border-radius: 8px;
  padding: 2px;
  margin-bottom: 8px;
  flex-wrap: wrap;
}
.pw-segment {
  border: 0;
  background: none;
  font: inherit;
  padding: 6px 16px;
  border-radius: 6px;
  cursor: pointer;
  color: var(--pw-muted);
}
.pw-segment.is-active {
  background: var(--pw-primary-soft);
  color: var(--pw-primary);
  font-weight: 600;
}
.pw-count {
  display: inline-block;
  margin-left: 6px;
  min-width: 18px;
  padding: 0 5px;
  border-radius: 9px;
  font-size: 11px;
  line-height: 18px;
  text-align: center;
  background: var(--pw-border);
  color: var(--pw-text);
}
.pw-textarea.pw-rules {
  min-height: 140px;
}
</style>
