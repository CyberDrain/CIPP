import { useState } from 'react'
import { buildVersionedHeaders } from '../utils/cippVersion'
import { impersonationCacheParams } from '../utils/impersonation'
import { cloudBackupDownloadFileName } from '../utils/cloud-backup'

const errorMessage = async (response) => {
  const body = await response.json().catch(() => null)
  return typeof body?.Results === 'string'
    ? body.Results
    : `The download failed (HTTP ${response.status}). Try again, or check the logbook.`
}

const fetchPart = async (params, part) => {
  const query = new URLSearchParams(
    Object.entries({
      ...params,
      Part: part,
      ...impersonationCacheParams(),
    }).filter(
      ([, value]) => value !== undefined && value !== null && value !== ''
    )
  )
  return fetch(`/api/ExecCloudBackupDownload?${query}`, {
    credentials: 'same-origin',
    headers: await buildVersionedHeaders(),
  })
}

const saveBlob = (blob, name) => {
  const url = URL.createObjectURL(blob)
  const link = document.createElement('a')
  link.href = url
  link.download = name
  document.body.appendChild(link)
  link.click()
  document.body.removeChild(link)
  URL.revokeObjectURL(url)
}

export const useCloudBackupDownload = () => {
  const [busy, setBusy] = useState(false)
  const [error, setError] = useState(null)
  const [progress, setProgress] = useState(null)

  const download = async (params, fallbackName = 'download') => {
    if (busy) return
    setBusy(true)
    setError(null)
    setProgress(null)
    let writable = null
    try {
      // Large exports come in parts; writing them straight to a file keeps them out of browser memory.
      if (
        typeof window !== 'undefined' &&
        typeof window.showSaveFilePicker === 'function'
      ) {
        try {
          const handle = await window.showSaveFilePicker({
            suggestedName: fallbackName,
          })
          writable = await handle.createWritable()
        } catch (pickerError) {
          if (pickerError?.name === 'AbortError') return
          writable = null
        }
      }

      const blobs = []
      let name = fallbackName
      let parts = 1
      for (let part = 0; part < parts; part += 1) {
        const response = await fetchPart(params, part)
        if (!response.ok) {
          setError(await errorMessage(response))
          if (writable) await writable.abort()
          writable = null
          return
        }
        if (part === 0) {
          parts = Math.max(
            1,
            Number(response.headers.get('X-CIPP-Download-Parts')) || 1
          )
          name = cloudBackupDownloadFileName(
            response.headers.get('Content-Disposition'),
            fallbackName
          )
        }
        setProgress(parts > 1 ? { part: part + 1, parts } : null)
        const blob = await response.blob()
        if (writable) {
          await writable.write(blob)
        } else {
          blobs.push(blob)
        }
      }

      if (writable) {
        await writable.close()
        writable = null
      } else {
        saveBlob(new Blob(blobs), name)
      }
    } catch {
      if (writable) await writable.abort().catch(() => {})
      setError('The download failed. Check your connection and try again.')
    } finally {
      setBusy(false)
      setProgress(null)
    }
  }

  return { download, busy, error, progress }
}
