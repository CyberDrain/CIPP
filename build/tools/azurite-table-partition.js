/*
 * Preloaded into azurite (NODE_OPTIONS=--require ...). Persists the table service as
 * __azurite_db_table__.json (the db shell plus a page manifest) and one file per page of
 * rows. A save rewrites only the pages whose rows, ids or revisions changed, and writes them
 * asynchronously.
 * Page boundaries come from each row's $loki, so an insert, update or delete touches
 * only its own page. The legacy single-file db and the LokiPartitioningAdapter
 * <db>.<n>.<page> layout both load, and are migrated on the first save.
 */
const crypto = require('crypto')
const fs = require('fs')
const fsp = require('fs/promises')
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
  // file -> { last, count, rev, closed }: a save skips an unchanged page; an open tail page is rewritten so appends extend it
  const pageState = new Map()
  let saved = null

  function read(file) {
    const text = fs.readFileSync(file, 'utf8')
    onDisk.set(file, hash(text))
    return text
  }

  async function write(file, text) {
    await fsp.writeFile(`${file}~`, text)
    await fsp.rename(`${file}~`, file)
  }

  function sweep(dbname, keep) {
    const dir = path.dirname(dbname)
    const page = new RegExp(`^${path.basename(dbname).replace(/\W/g, '\\$&')}\\.[^.]+\\.\\d+$`)
    return fs
      .readdirSync(dir)
      .filter((name) => page.test(name) && !keep.has(path.join(dir, name)))
      .map((name) => path.join(dir, name))
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
            let rev = 0
            let doc
            const text = fs.readFileSync(file, 'utf8')
            const rows = text.split('\n')
            for (const row of rows) {
              doc = JSON.parse(row)
              rev += doc.meta?.revision ?? 0
              coll.data.push(doc)
            }
            pageState.set(file, { last: doc.$loki, count: rows.length, rev, closed: isBoundary(doc.$loki) || text.length >= PAGE_MAX })
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
      if (!saved) pageState.clear()
      callback(dbref)
    },

    // Rows are serialised synchronously (the copy Loki hands over shares their objects); the file I/O runs after.
    exportDatabase(dbname, dbref, callback) {
      const jobs = []
      let shell
      const previous = saved
      try {
        const pages = {}
        for (const coll of dbref.collections) {
          const files = (pages[coll.name] = [])
          const prefix = `${dbname}.${encodeURIComponent(coll.name)}.`
          const data = coll.data
          let i = 0
          while (i < data.length) {
            const file = prefix + data[i].$loki
            const known = pageState.get(file)
            if (known && data[i + known.count - 1]?.$loki === known.last && (known.closed || i + known.count === data.length)) {
              let rev = 0
              for (let j = i; j < i + known.count; j++) rev += data[j].meta?.revision ?? 0
              if (rev === known.rev) {
                files.push(file)
                i += known.count
                continue
              }
            }
            const rows = []
            let size = 0
            let rev = 0
            let doc
            do {
              doc = data[i++]
              const row = JSON.stringify(doc)
              rows.push(row)
              size += row.length + 1
              rev += doc.meta?.revision ?? 0
            } while (i < data.length && !isBoundary(doc.$loki) && size < PAGE_MAX)
            jobs.push([file, rows.join('\n')])
            pageState.set(file, { last: doc.$loki, count: rows.length, rev, closed: isBoundary(doc.$loki) || size >= PAGE_MAX })
            files.push(file)
          }
        }
        const text = dbref.serializeDestructured({ partitioned: true, partition: -1 })
        shell = `${text.slice(0, -1)},"pages":${JSON.stringify(pages)}}`
        saved = pages
      } catch (err) {
        saved = null
        pageState.clear()
        callback(err)
        return
      }

      const keep = new Set(Object.values(saved).flat())
      const digest = hash(shell)
      ;(async () => {
        await Promise.all(jobs.map(([file, text]) => write(file, text)))
        if (onDisk.get(dbname) !== digest) {
          await write(dbname, shell)
          onDisk.set(dbname, digest)
        }
        const stale = previous ? Object.values(previous).flat().filter((file) => !keep.has(file)) : sweep(dbname, keep)
        for (const file of stale) pageState.delete(file)
        await Promise.all(stale.map((file) => fsp.rm(file, { force: true })))
      })().then(
        () => callback(null),
        (err) => {
          saved = null
          pageState.clear()
          onDisk.delete(dbname)
          callback(err)
        }
      )
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
