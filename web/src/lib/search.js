export const normalizeQuery = (query) => query.trim().toLowerCase().replace(/^\./, '')

export const getEntryExt = (entry) => {
  if (entry?.ext) {
    return String(entry.ext).toLowerCase()
  }

  const name = String(entry?.name || '')
  const parts = name.split('.')
  if (parts.length < 2) {
    return ''
  }

  return parts.at(-1).toLowerCase()
}

export const entryMatchesQuery = (entry, normalizedQuery) => {
  if (!normalizedQuery) {
    return false
  }

  const nameMatches = String(entry?.name || '').toLowerCase().includes(normalizedQuery)
  const extMatches = entry?.type === 'file' && getEntryExt(entry) === normalizedQuery

  return nameMatches || extMatches
}

export const driveMatchesQuery = (drive, normalizedQuery) => {
  if (!normalizedQuery) {
    return true
  }

  const driveNameMatches = String(drive?.name || '').toLowerCase().includes(normalizedQuery)
  const entries = Array.isArray(drive?.entries) ? drive.entries : []

  return driveNameMatches || entries.some((entry) => entryMatchesQuery(entry, normalizedQuery))
}

export const getTopMatches = (entries, normalizedQuery, limit = 5) => {
  if (!normalizedQuery) {
    return []
  }

  return entries
    .filter((entry) => entryMatchesQuery(entry, normalizedQuery))
    .sort((a, b) => (b?.sizeBytes || 0) - (a?.sizeBytes || 0))
    .slice(0, limit)
}
