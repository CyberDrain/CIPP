/*
 * Preloaded into azurite (NODE_OPTIONS=--require ...). Persists the table service as
 * __azurite_db_table__.json (the db shell plus a page manifest) and one file per page of
 * rows. A save skips unchanged tables and rewrites only the pages whose content changed.
 * Page boundaries come from each row's $loki, so an insert, update or delete touches
 * only its own page. The legacy single-file db and the LokiPartitioningAdapter
 * <db>.<n>.<page> layout both load, and are migrated on the first save.
 */
const crypto = require('crypto')
const fs = require('fs')
const path = require('path')
const Loki = require(require.resolve('lokijs', { paths: ['/opt/azurite'] }))

const TABLE_DB = '__azurite_db_table__.json'
const PAGE_ROWS = 256
const PAGE_MAX = 256 * 1024 * 1024
const LEGACY_DELIMITER = '$<\n'

const isBoundary = (id) => Math.imul(id, 0x9e3779b1) >>> 0 < 0x100000000 / PAGE_ROWS
const hash = (text) => crypto.createHash('sha1').update(text).digest('base64')

function createAdapter() {
  const onDisk = new Map()
  let saved = null

  function read(file) {
    const text = fs.readFileSync(file, 'utf8')
    onDisk.set(file, hash(text))
    return text
  }

  function write(file, text) {
    const digest = hash(text)
    if (onDisk.get(file) === digest) return
    fs.writeFileSync(`${file}~`, text)
    fs.renameSync(`${file}~`, file)
    onDisk.set(file, digest)
  }

  function sweep(dbname, keep) {
    const dir = path.dirname(dbname)
    const page = new RegExp(`^${path.basename(dbname).replace(/\W/g, '\\$&')}\\.[^.]+\\.\\d+$`)
    for (const name of fs.readdirSync(dir)) {
      const file = path.join(dir, name)
      if (page.test(name) && !keep.has(file)) {
        fs.unlinkSync(file)
        onDisk.delete(file)
      }
    }
  }

  return {
    mode: 'reference',

    loadDatabase(dbname, callback) {
      let db
      try {
        db = JSON.parse(read(dbname))
      } catch (err) {
        callback(err.code === 'ENOENT' ? null : err)
        return
      }
      const manifest = db.pages
      delete db.pages
      const dbref = new Loki(dbname)
      dbref.loadJSONObject(db)
      db = null

      dbref.collections.forEach((coll, index) => {
        if (manifest) {
          for (const file of manifest[coll.name] || []) {
            for (const row of read(file).split('\n')) coll.data.push(JSON.parse(row))
          }
          return
        }
        if (coll.data.length) return
        for (let page = 0; fs.existsSync(`${dbname}.${index}.${page}`); page++) {
          const rows = fs.readFileSync(`${dbname}.${index}.${page}`, 'utf8').split(LEGACY_DELIMITER)
          for (const row of rows) if (row) coll.data.push(JSON.parse(row))
          if (rows[rows.length - 1] === '') break
        }
      })
      // Rows pushed straight into coll.data bypass Loki's indexes; without a rebuild, key lookups miss and upserts duplicate.
      dbref.collections.forEach((coll) => {
        coll.ensureId()
        coll.ensureAllIndexes(true)
      })
      saved = manifest || null
      callback(dbref)
    },

    exportDatabase(dbname, dbref, callback) {
      try {
        const pages = {}
        for (const coll of dbref.collections) {
          if (saved?.[coll.name] && !coll.dirty) {
            pages[coll.name] = saved[coll.name]
            continue
          }
          const files = (pages[coll.name] = [])
          const prefix = `${dbname}.${encodeURIComponent(coll.name)}.`
          let rows = []
          let size = 0
          let first
          coll.data.forEach((doc, index) => {
            const row = JSON.stringify(doc)
            if (!rows.length) first = doc.$loki
            rows.push(row)
            size += row.length + 1
            if (isBoundary(doc.$loki) || size >= PAGE_MAX || index === coll.data.length - 1) {
              write(prefix + first, rows.join('\n'))
              files.push(prefix + first)
              rows = []
              size = 0
            }
          })
        }

        const shell = dbref.serializeDestructured({ partitioned: true, partition: -1 })
        write(dbname, `${shell.slice(0, -1)},"pages":${JSON.stringify(pages)}}`)
        sweep(dbname, new Set(Object.values(pages).flat()))
        saved = pages
        callback(null)
      } catch (err) {
        saved = null
        callback(err)
      }
    },
  }
}

const configureOptions = Loki.prototype.configureOptions
Loki.prototype.configureOptions = function (options, initialConfig) {
  if (initialConfig && options?.persistenceMethod === 'fs' && this.filename.endsWith(TABLE_DB)) {
    options = { ...options, adapter: createAdapter() }
  }
  return configureOptions.call(this, options, initialConfig)
}
