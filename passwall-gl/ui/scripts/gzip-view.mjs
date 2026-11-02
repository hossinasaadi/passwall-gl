// Gzip the built page into the package tree, where GL's nginx serves it from.
import { readFileSync, writeFileSync, mkdirSync } from 'node:fs'
import { gzipSync } from 'node:zlib'
import { dirname, resolve } from 'node:path'
import { fileURLToPath } from 'node:url'

const here = dirname(fileURLToPath(import.meta.url))
const name = 'gl-sdk4-ui-passwall.common.js'
const src = resolve(here, '../dist', name)
const dest = resolve(here, '../../root/www/views', name + '.gz')

const code = readFileSync(src, 'utf8')
if (/require\(["']vue["']\)/.test(code)) {
  throw new Error('bundle imports vue; GL provides Vue, so the page must not import it')
}
mkdirSync(dirname(dest), { recursive: true })
writeFileSync(dest, gzipSync(code, { level: 9, mtime: 0 }))
console.log(`wrote ${dest} (${code.length} bytes before gzip)`)
