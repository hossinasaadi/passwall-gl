import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue2'
import { fileURLToPath } from 'node:url'

const here = (p) => fileURLToPath(new URL(p, import.meta.url))

// GL's admin UI loads each page from /www/views/gl-sdk4-ui-<view>.common.js(.gz)
// as a CommonJS module whose export is a Vue 2 component. The host provides
// Vue, so the bundle must not import it, and CSS has to ride inside the JS.
const VIEW = 'passwall'

function inlineCss() {
  return {
    name: 'inline-css',
    apply: 'build',
    enforce: 'post',
    generateBundle(_, bundle) {
      let css = ''
      for (const [file, asset] of Object.entries(bundle)) {
        if (file.endsWith('.css')) {
          css += asset.source
          delete bundle[file]
        }
      }
      if (!css) return
      const inject =
        '(function(){if(typeof document==="undefined"||document.getElementById("pw-gl-style"))return;' +
        'var s=document.createElement("style");s.id="pw-gl-style";s.textContent=' +
        JSON.stringify(css) + ';document.head.appendChild(s);})();\n'
      for (const chunk of Object.values(bundle)) {
        if (chunk.type === 'chunk' && chunk.isEntry) chunk.code = inject + chunk.code
      }
    },
  }
}

export default defineConfig({
  root: here('./dev'),
  plugins: [vue(), inlineCss()],
  resolve: {
    // The dev preview mounts the page itself, so it needs the template compiler.
    alias: { vue: 'vue/dist/vue.esm.js' },
  },
  build: {
    outDir: here('./dist'),
    emptyOutDir: true,
    cssCodeSplit: false,
    minify: 'esbuild',
    lib: {
      entry: here('./src/index.js'),
      formats: ['cjs'],
      fileName: () => `gl-sdk4-ui-${VIEW}.common.js`,
    },
    rollupOptions: {
      external: ['vue'],
      output: { exports: 'default' },
    },
  },
})
