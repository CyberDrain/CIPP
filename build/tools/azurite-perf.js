/*
 * Preloaded into azurite (NODE_OPTIONS=--require ...). Patches the table service hot paths:
 * - Without --debug azurite discards every log level, yet each call still builds its message, and several
 *   JSON.stringify whole request/response bodies ($batch, queries). Those calls are skipped.
 * - Entity collections drop LokiJS's PartitionKey/RowKey binary indexes, which cost O(rows) per insert, delete and
 *   update (array splices and a linear scan), for a PartitionKey -> RowKey -> entity map kept current from the
 *   collection's insert/update/delete events. Point lookups read the map; queries walk a sorted copy of the
 *   partition (or table) that is rebuilt only after a write to it.
 * - Batches run one at a time: stock azurite shares one rollback state between concurrent batches and can wedge it.
 */
const Module = require('module')
const path = require('path')

const ROOT = '/opt/azurite/dist/src/'
const STORE = `${ROOT}table/persistence/LokiTableMetadataStore.js`
const logging = process.argv.some((arg) => arg === '--debug' || arg === '-d')
const PARTITION = /^\s*\(?\s*PartitionKey\s+eq\s+'((?:[^']|'')*)'/

const before = (a, pk, rk) => a.PartitionKey < pk || (a.PartitionKey === pk && a.RowKey < rk)
const order = (a, b) => (a.PartitionKey === b.PartitionKey ? (a.RowKey > b.RowKey ? 1 : a.RowKey === b.RowKey ? 0 : -1) : a.PartitionKey > b.PartitionKey ? 1 : -1)

// without or/not the filter is a pure conjunction, so a leading PartitionKey eq bounds every match
function partitionOf(filter) {
  if (!filter || /\b(or|not)\b/i.test(filter)) return undefined
  return filter.match(PARTITION)?.[1].replace(/''/g, "'")
}

function attachKeys(coll) {
  const keys = { parts: new Map(), sorted: new Map(), all: null }
  const touched = (pk) => {
    keys.sorted.delete(pk)
    keys.all = null
  }
  const put = (doc) => {
    let part = keys.parts.get(doc.PartitionKey)
    if (!part) keys.parts.set(doc.PartitionKey, (part = new Map()))
    part.set(doc.RowKey, doc)
    touched(doc.PartitionKey)
  }
  const drop = (doc) => {
    const part = keys.parts.get(doc.PartitionKey)
    if (part?.get(doc.RowKey) === doc) {
      part.delete(doc.RowKey)
      if (!part.size) keys.parts.delete(doc.PartitionKey)
    }
    touched(doc.PartitionKey)
  }
  for (const doc of coll.data) put(doc)
  coll.on('insert', (docs) => (Array.isArray(docs) ? docs.forEach(put) : put(docs)))
  coll.on('update', put)
  coll.on('delete', drop)
  coll.binaryIndices = {}
  coll.__keys = keys
}

function sortedRows(coll, pk) {
  const keys = coll.__keys
  if (pk === undefined) return (keys.all ??= coll.data.slice().sort(order))
  let rows = keys.sorted.get(pk)
  if (!rows) keys.sorted.set(pk, (rows = [...(keys.parts.get(pk)?.values() ?? [])].sort(order)))
  return rows
}

function patchStore(Store, QueryGenerator, Collection) {
  // A batch's rollback state is one pair of arrays shared by the whole store. Batches that interleave across an await mix
  // their rows; a failed one rolls the other's rows back against its own table, the rollback throws before the arrays are
  // reset, and every later batch fails "Transaction Overlap!" (a bodyless 500) until restart. Batches run one at a time, and
  // the state is reset however a batch ends. A batch that never ends is stepped past after a minute.
  let tail = Promise.resolve()
  let holder = null
  Store.prototype.beginBatchTransaction = async function (batchId) {
    const previous = tail
    let release
    tail = new Promise((resolve) => (release = resolve))
    let timer
    await Promise.race([previous, new Promise((resolve) => (timer = setTimeout(resolve, 60000)))])
    clearTimeout(timer)
    holder = { batchId, release }
    this.transactionRollbackTheseEntities = []
    this.transactionDeleteTheseEntities = []
  }
  const endBatchTransaction = Store.prototype.endBatchTransaction
  Store.prototype.endBatchTransaction = async function (account, table, batchId, context, succeeded) {
    // the batch was refused before it began: there is nothing of its own to roll back or reset
    if (holder?.batchId !== batchId) return
    try {
      await endBatchTransaction.call(this, account, table, batchId, context, succeeded)
    } finally {
      this.transactionRollbackTheseEntities = []
      this.transactionDeleteTheseEntities = []
      const { release } = holder
      holder = null
      release()
    }
  }

  const findOne = Collection.prototype.findOne
  Collection.prototype.findOne = function (query) {
    const keys = this.__keys
    if (keys && typeof query?.PartitionKey === 'string' && typeof query.RowKey === 'string' && Object.keys(query).length === 2) {
      return keys.parts.get(query.PartitionKey)?.get(query.RowKey) ?? null
    }
    return findOne.call(this, query)
  }

  const getEntityCollection = Store.prototype.getEntityCollection
  Store.prototype.getEntityCollection = function (...args) {
    const coll = getEntityCollection.apply(this, args)
    if (!coll.__keys) attachKeys(coll)
    return coll
  }

  const queryTableEntities = Store.prototype.queryTableEntities
  Store.prototype.queryTableEntities = async function (context, account, table, queryOptions, nextPartitionKey, nextRowKey) {
    const nextPK = this.decodeContinuationHeader(nextPartitionKey)
    const nextRK = this.decodeContinuationHeader(nextRowKey)
    // stock azurite matches nothing for a row-key-only continuation; leave that edge to it
    if (nextPK === undefined && nextRK !== undefined) return queryTableEntities.apply(this, arguments)
    const coll = this.getEntityCollection(account, table, context)
    const where = QueryGenerator.generateQueryForPersistenceLayer(queryOptions, context)
    const max = this.getMaxResultsOption(queryOptions)
    const rows = sortedRows(coll, partitionOf(queryOptions.filter))
    let i = 0
    if (nextPK !== undefined) {
      let hi = rows.length
      while (i < hi) {
        const mid = (i + hi) >>> 1
        if (before(rows[mid], nextPK, nextRK ?? '')) i = mid + 1
        else hi = mid
      }
    }
    const result = []
    for (; i < rows.length && result.length <= max; i++) if (where(rows[i])) result.push(rows[i])
    const response = this.adjustQueryResultforTop(result, max)
    return [result, response.nextPartitionKeyResponse, response.nextRowKeyResponse]
  }
}

const compile = Module.prototype._compile
Module.prototype._compile = function (content, filename) {
  if (!filename.startsWith(ROOT)) return compile.call(this, content, filename)
  if (!logging) content = content.replace(/\bthis\.logger\.(error|warn|info|verbose|debug)\(/g, 'false && this.logger.$1(')
  const result = compile.call(this, content, filename)
  // An internal error inside a batch (not a storage error) has no status code; azurite then fails serialising it and
  // answers a bodyless 500 with nothing logged. Print it, as nothing else will.
  if (filename === `${ROOT}table/batch/TableBatchSerialization.js`) {
    const Serialization = this.exports.TableBatchSerialization
    const serializeError = Serialization.prototype.serializeError
    Serialization.prototype.serializeError = function (err, ...rest) {
      if (err?.statusCode === undefined) console.error('azurite-perf: batch operation failed:', err?.stack || err)
      return serializeError.call(this, err, ...rest)
    }
  }
  if (filename === STORE) {
    const Store = this.exports.default
    const methods = ['getEntityCollection', 'queryTableEntities', 'decodeContinuationHeader', 'getMaxResultsOption', 'adjustQueryResultforTop', 'beginBatchTransaction', 'endBatchTransaction']
    if (methods.every((m) => typeof Store?.prototype?.[m] === 'function')) {
      const QueryGenerator = this.require(path.join(path.dirname(STORE), 'LokiTableStoreQueryGenerator')).default
      patchStore(Store, QueryGenerator, this.require('lokijs').Collection)
    } else {
      console.warn('azurite-perf: LokiTableMetadataStore changed shape; entity index patch skipped')
    }
  }
  return result
}
