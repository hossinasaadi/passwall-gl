<template>
  <div class="pw">
    <div class="pw-tabs" role="tablist">
      <button
        v-for="tab in tabs"
        :key="tab.id"
        type="button"
        role="tab"
        :aria-selected="current === tab.id"
        :class="['pw-tab', { 'is-active': current === tab.id }]"
        @click="current = tab.id"
      >
        {{ tab.label }}
      </button>
    </div>
    <keep-alive>
      <component :is="view" @goto="current = $event" />
    </keep-alive>
  </div>
</template>

<script>
import StatusView from './views/StatusView.vue'
import NodesView from './views/NodesView.vue'
import LogView from './views/LogView.vue'

const VIEWS = { status: StatusView, nodes: NodesView, log: LogView }

export default {
  name: 'PasswallPage',
  data() {
    return {
      current: 'status',
      tabs: [
        { id: 'status', label: 'Basic Settings' },
        { id: 'nodes', label: 'Node List' },
        { id: 'log', label: 'Runtime Logs' },
      ],
    }
  },
  computed: {
    view() {
      return VIEWS[this.current]
    },
  },
}
</script>

<style>
.pw {
  --pw-bg: #f5f7fa;
  --pw-card: #fff;
  --pw-text: #1f2329;
  --pw-muted: #8a8f99;
  --pw-border: #e5e7eb;
  --pw-primary: #2b6de5;
  --pw-primary-soft: #e8f0fd;
  --pw-ok: #1a9f53;
  --pw-bad: #d6453d;
  --pw-warn: #c27c0e;
  color: var(--pw-text);
  font-size: 14px;
  line-height: 1.5;
  max-width: 1100px;
}
.pw *,
.pw *::before,
.pw *::after {
  box-sizing: border-box;
}
.pw-tabs {
  display: flex;
  gap: 4px;
  overflow-x: auto;
  border-bottom: 1px solid var(--pw-border);
  margin-bottom: 16px;
}
.pw-tab {
  border: 0;
  background: none;
  padding: 10px 14px;
  font: inherit;
  color: var(--pw-muted);
  cursor: pointer;
  border-bottom: 2px solid transparent;
  white-space: nowrap;
}
.pw-tab.is-active {
  color: var(--pw-primary);
  border-bottom-color: var(--pw-primary);
  font-weight: 600;
}
.pw-card {
  background: var(--pw-card);
  border-radius: 8px;
  padding: 16px 20px;
  margin-bottom: 16px;
  box-shadow: 0 1px 4px rgba(0, 0, 0, 0.06);
}
.pw-card-title {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 12px;
  font-size: 15px;
  font-weight: 600;
  margin: 0 0 12px;
}
.pw-row {
  display: flex;
  align-items: center;
  justify-content: space-between;
  gap: 16px;
  padding: 10px 0;
  border-top: 1px solid var(--pw-border);
}
.pw-row:first-of-type {
  border-top: 0;
}
.pw-row-label {
  min-width: 0;
}
.pw-row-help {
  color: var(--pw-muted);
  font-size: 12px;
}
.pw-btn {
  border: 1px solid var(--pw-border);
  background: #fff;
  color: var(--pw-text);
  border-radius: 6px;
  padding: 6px 14px;
  font: inherit;
  cursor: pointer;
  white-space: nowrap;
}
.pw-btn:hover:not(:disabled) {
  border-color: var(--pw-primary);
  color: var(--pw-primary);
}
.pw-btn:disabled {
  opacity: 0.5;
  cursor: default;
}
.pw-btn-primary {
  background: var(--pw-primary);
  border-color: var(--pw-primary);
  color: #fff;
}
.pw-btn-primary:hover:not(:disabled) {
  color: #fff;
  opacity: 0.9;
}
.pw-btn-danger:hover:not(:disabled) {
  border-color: var(--pw-bad);
  color: var(--pw-bad);
}
.pw-btn-sm {
  padding: 2px 10px;
  font-size: 12px;
}
.pw-input,
.pw-select,
.pw-textarea {
  border: 1px solid var(--pw-border);
  border-radius: 6px;
  padding: 6px 10px;
  font: inherit;
  color: inherit;
  background: #fff;
  max-width: 100%;
}
.pw-textarea {
  width: 100%;
  min-height: 120px;
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  font-size: 12px;
}
.pw-select {
  min-width: 220px;
}
.pw-switch {
  position: relative;
  display: inline-block;
  width: 40px;
  height: 22px;
  flex: none;
}
.pw-switch input {
  opacity: 0;
  width: 0;
  height: 0;
}
.pw-switch span {
  position: absolute;
  inset: 0;
  background: #c9ccd2;
  border-radius: 22px;
  transition: background 0.15s;
  cursor: pointer;
}
.pw-switch span::before {
  content: '';
  position: absolute;
  width: 18px;
  height: 18px;
  left: 2px;
  top: 2px;
  background: #fff;
  border-radius: 50%;
  transition: transform 0.15s;
}
.pw-switch input:checked + span {
  background: var(--pw-primary);
}
.pw-switch input:checked + span::before {
  transform: translateX(18px);
}
.pw-switch input:focus-visible + span {
  outline: 2px solid var(--pw-primary);
  outline-offset: 2px;
}
.pw-dot {
  display: inline-block;
  width: 8px;
  height: 8px;
  border-radius: 50%;
  margin-right: 6px;
  background: var(--pw-muted);
}
.pw-dot.is-ok {
  background: var(--pw-ok);
}
.pw-dot.is-bad {
  background: var(--pw-bad);
}
.pw-muted {
  color: var(--pw-muted);
}
.pw-ok {
  color: var(--pw-ok);
}
.pw-bad {
  color: var(--pw-bad);
}
.pw-warn {
  color: var(--pw-warn);
}
.pw-error {
  background: #fdecea;
  color: var(--pw-bad);
  border-radius: 6px;
  padding: 8px 12px;
  margin-bottom: 12px;
}
@media (max-width: 640px) {
  .pw-card {
    padding: 14px;
  }
  .pw-row {
    flex-wrap: wrap;
  }
  .pw-select {
    min-width: 0;
    width: 100%;
  }
}
</style>
