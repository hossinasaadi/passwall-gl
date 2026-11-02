<template>
  <section class="pw-card">
    <h3 class="pw-card-title">
      <span>Runtime logs</span>
      <span class="pw-toolbar pw-log-tools">
        <label class="pw-muted"><input v-model="follow" type="checkbox" /> Auto refresh</label>
        <button type="button" class="pw-btn pw-btn-sm" @click="load">Refresh</button>
        <button type="button" class="pw-btn pw-btn-sm pw-btn-danger" @click="clear">Clear</button>
      </span>
    </h3>
    <div v-if="error" class="pw-error">{{ error }}</div>
    <pre ref="box" class="pw-log">{{ text || 'The log is empty.' }}</pre>
  </section>
</template>

<script>
import { rpc } from '../rpc.js'

export default {
  name: 'LogView',
  data() {
    return { text: '', follow: true, error: '', timer: null }
  },
  activated() {
    this.load()
    this.timer = setInterval(() => this.follow && this.load(), 3000)
  },
  deactivated() {
    clearInterval(this.timer)
  },
  beforeDestroy() {
    clearInterval(this.timer)
  },
  methods: {
    load() {
      return rpc('get_log')
        .then((t) => {
          this.error = ''
          const box = this.$refs.box
          const atBottom = box && box.scrollTop + box.clientHeight >= box.scrollHeight - 8
          this.text = t
          if (atBottom) this.$nextTick(() => (box.scrollTop = box.scrollHeight))
        })
        .catch((e) => (this.error = e.message))
    },
    clear() {
      rpc('clear_log')
        .then(this.load)
        .catch((e) => (this.error = e.message))
    },
  },
}
</script>

<style>
.pw-log-tools {
  margin: 0;
  font-weight: 400;
}
.pw-log {
  margin: 0;
  height: 480px;
  overflow: auto;
  background: #1e1f22;
  color: #d4d4d4;
  border-radius: 6px;
  padding: 12px;
  font: 12px/1.5 ui-monospace, SFMono-Regular, Menlo, monospace;
  white-space: pre-wrap;
  word-break: break-all;
}
</style>
