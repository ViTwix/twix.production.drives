import { useEffect, useMemo, useState } from 'react'
import { formatBytes, formatDate, pluralizeUk } from './lib/format'
import { driveMatchesQuery, entryMatchesQuery, getTopMatches, normalizeQuery } from './lib/search'

const DATA_URL =
  'https://raw.githubusercontent.com/ViTwix/twix.production.drives/main/data/drives.json'
const DRIVE_NAME_COLLATOR = new Intl.Collator(undefined, { numeric: true, sensitivity: 'base' })
const EXCLUDED_ENTRY_NAMES = new Set([
  'system volume information',
  '$recycle.bin',
  'recycler',
])

const getUsageColorClass = (percent) => {
  if (percent > 90) {
    return 'bg-[var(--color-danger)]'
  }

  if (percent >= 70) {
    return 'bg-[var(--color-warn)]'
  }

  return 'bg-[var(--color-ok)]'
}

const compareEntryNames = (a, b) =>
  DRIVE_NAME_COLLATOR.compare(String(a?.name || ''), String(b?.name || ''))

const sortEntriesLikeFinder = (entries) =>
  [...entries].sort((a, b) => {
    const aRank = a?.type === 'folder' ? 0 : 1
    const bRank = b?.type === 'folder' ? 0 : 1
    if (aRank !== bRank) {
      return aRank - bRank
    }
    return compareEntryNames(a, b)
  })

const filterVisibleEntries = (entries) =>
  entries.filter((entry) => {
    const name = String(entry?.name || '')
    if (!name || name.startsWith('.')) {
      return false
    }
    return !EXCLUDED_ENTRY_NAMES.has(name.toLowerCase())
  })

const promoteMatchedEntries = (entries, normalizedQuery) => {
  if (!normalizedQuery) {
    return entries
  }

  return [...entries].sort((a, b) => {
    const aMatched = entryMatchesQuery(a, normalizedQuery) ? 1 : 0
    const bMatched = entryMatchesQuery(b, normalizedQuery) ? 1 : 0
    if (aMatched !== bMatched) {
      return bMatched - aMatched
    }
    return 0
  })
}

const EntryIcon = ({ type }) => {
  if (type === 'folder') {
    return (
      <svg
        aria-hidden="true"
        viewBox="0 0 20 20"
        className="inline-block h-4 w-4 shrink-0 text-sky-400 align-[-2px]"
      >
        <path
          d="M2.5 6.5A2.5 2.5 0 0 1 5 4h2.1c.53 0 1.04.21 1.41.59l.9.9c.19.18.44.29.7.29H15a2.5 2.5 0 0 1 2.5 2.5v5.22A2.5 2.5 0 0 1 15 16H5a2.5 2.5 0 0 1-2.5-2.5z"
          fill="currentColor"
          opacity="0.92"
        />
        <path
          d="M2.5 8.4h15"
          stroke="rgba(255,255,255,0.35)"
          strokeWidth="0.9"
          strokeLinecap="round"
        />
      </svg>
    )
  }

  return (
    <svg
      aria-hidden="true"
      viewBox="0 0 20 20"
      className="inline-block h-4 w-4 shrink-0 text-slate-300 align-[-2px]"
    >
      <path
        d="M5 2.75h6.33c.4 0 .78.16 1.06.44l2.42 2.42c.28.28.44.66.44 1.06V16A2.25 2.25 0 0 1 13 18.25H5A2.25 2.25 0 0 1 2.75 16V5A2.25 2.25 0 0 1 5 2.75Z"
        fill="currentColor"
        opacity="0.95"
      />
      <path
        d="M11.25 2.75v2.8c0 .62.5 1.12 1.12 1.12h2.88"
        stroke="rgba(10,10,11,0.35)"
        strokeWidth="1"
        strokeLinecap="round"
      />
      <path
        d="M5.9 9.4h8.2M5.9 11.6h8.2M5.9 13.8h5.5"
        stroke="rgba(10,10,11,0.35)"
        strokeWidth="0.9"
        strokeLinecap="round"
      />
    </svg>
  )
}

const highlightText = (value, query) => {
  if (!query) {
    return value
  }

  const normalizedValue = value.toLowerCase()
  const fromIndex = normalizedValue.indexOf(query)

  if (fromIndex < 0) {
    return value
  }

  const toIndex = fromIndex + query.length
  return (
    <>
      {value.slice(0, fromIndex)}
      <mark className="rounded bg-[var(--color-accent)]/25 px-0.5 text-[var(--color-text)]">
        {value.slice(fromIndex, toIndex)}
      </mark>
      {value.slice(toIndex)}
    </>
  )
}

const App = () => {
  const [data, setData] = useState(null)
  const [query, setQuery] = useState('')
  const [isLoading, setIsLoading] = useState(true)
  const [errorMessage, setErrorMessage] = useState('')
  const [expandedDriveName, setExpandedDriveName] = useState('')
  const [reloadKey, setReloadKey] = useState(0)

  useEffect(() => {
    let isMounted = true

    const fetchData = async () => {
      setIsLoading(true)
      setErrorMessage('')

      try {
        const response = await fetch(`${DATA_URL}?t=${Date.now()}&r=${reloadKey}`)
        if (!response.ok) {
          throw new Error(`HTTP ${response.status}`)
        }

        const json = await response.json()
        if (isMounted) {
          setData({
            updatedAt: json?.updatedAt ?? null,
            drives: Array.isArray(json?.drives) ? json.drives : [],
          })
        }
      } catch {
        if (isMounted) {
          setErrorMessage('Не вдалося завантажити дані')
          setData(null)
        }
      } finally {
        if (isMounted) {
          setIsLoading(false)
        }
      }
    }

    fetchData()

    return () => {
      isMounted = false
    }
  }, [reloadKey])

  const normalizedQuery = useMemo(() => normalizeQuery(query), [query])

  const drives = useMemo(() => {
    const source = Array.isArray(data?.drives) ? data.drives : []
    const byName = (a, b) => DRIVE_NAME_COLLATOR.compare(String(a?.name || ''), String(b?.name || ''))
    return [...source].sort(byName)
  }, [data])

  const visibleDrives = useMemo(
    () => drives.filter((drive) => driveMatchesQuery(drive, normalizedQuery)),
    [drives, normalizedQuery],
  )

  const handleRetry = () => setReloadKey((prev) => prev + 1)
  const getDriveDetailEntries = (drive) => {
    const entries = filterVisibleEntries(Array.isArray(drive?.entries) ? drive.entries : [])
    const sorted = sortEntriesLikeFinder(entries)
    return promoteMatchedEntries(sorted, normalizedQuery)
  }

  return (
    <div className="mx-auto min-h-screen w-full max-w-6xl px-4 py-8 sm:px-6 lg:px-8">
      <header className="sticky top-0 z-10 mb-6 rounded-2xl border border-[var(--color-border)]/70 bg-[var(--color-bg)]/85 p-4 backdrop-blur sm:p-5">
        <div className="mb-4 flex flex-col gap-3 sm:flex-row sm:items-start sm:justify-between">
          <div>
            <h1 className="text-2xl font-semibold tracking-tight sm:text-3xl">Twix Production Drives</h1>
            <p className="mt-1 text-sm text-[var(--color-text-muted)]">
              Оновлено: {data?.updatedAt ? formatDate(data.updatedAt) : '—'}
            </p>
          </div>
          <button
            type="button"
            onClick={handleRetry}
            className="inline-flex h-10 items-center justify-center rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)] px-4 text-sm font-medium text-[var(--color-text-muted)] transition hover:border-[var(--color-accent)]/50 hover:text-[var(--color-text)]"
          >
            Оновити дані
          </button>
        </div>

        <div className="grid gap-3 sm:grid-cols-[1fr] sm:items-center">
          <input
            type="search"
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            className="h-11 w-full rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)] px-4 text-sm text-[var(--color-text)] outline-none transition focus:border-[var(--color-accent)]"
            placeholder="Пошук за назвою диска, папки або файла…"
          />
        </div>
      </header>

      {isLoading ? (
        <section className="space-y-3">
          {[1, 2, 3].map((item) => (
            <div
              key={item}
              className="h-40 animate-pulse rounded-2xl border border-[var(--color-border)] bg-[var(--color-surface)]"
            />
          ))}
        </section>
      ) : null}

      {!isLoading && errorMessage ? (
        <section className="rounded-2xl border border-[var(--color-border)] bg-[var(--color-surface)] p-6">
          <p className="text-sm text-[var(--color-text)]">{errorMessage}</p>
          <button
            type="button"
            onClick={handleRetry}
            className="mt-4 rounded-lg border border-[var(--color-border)] px-3 py-2 text-sm transition hover:bg-[var(--color-surface-elevated)]"
          >
            Спробувати ще раз
          </button>
        </section>
      ) : null}

      {!isLoading && !errorMessage && drives.length === 0 ? (
        <section className="rounded-2xl border border-[var(--color-border)] bg-[var(--color-surface)] p-6 text-sm text-[var(--color-text-muted)]">
          Ще немає сканованих дисків. Запустіть скрипт у /scripts/
        </section>
      ) : null}

      {!isLoading && !errorMessage && drives.length > 0 && visibleDrives.length === 0 ? (
        <section className="rounded-2xl border border-[var(--color-border)] bg-[var(--color-surface)] p-6 text-sm text-[var(--color-text-muted)]">
          Нічого не знайдено за запитом «{query.trim()}»
        </section>
      ) : null}

      {!isLoading && !errorMessage && visibleDrives.length > 0 ? (
        <section className="space-y-3">
          {visibleDrives.map((drive) => {
            const entries = filterVisibleEntries(Array.isArray(drive?.entries) ? drive.entries : [])
            const foldersCount = entries.filter((entry) => entry?.type === 'folder').length
            const filesCount = entries.filter((entry) => entry?.type === 'file').length
            const totalBytes = drive?.totalBytes || 0
            const usedBytes = drive?.usedBytes || 0
            const usagePercent = totalBytes > 0 ? Math.min(100, Math.round((usedBytes / totalBytes) * 100)) : 0
            const matches = getTopMatches(entries, normalizedQuery)

            const isExpanded = expandedDriveName === drive?.name
            const detailEntries = getDriveDetailEntries(drive)

            return (
              <article
                key={drive?.name}
                onClick={() =>
                  setExpandedDriveName((prev) => (prev === drive?.name ? '' : String(drive?.name || '')))
                }
                className="card-surface w-full cursor-pointer text-left transition hover:border-[var(--color-accent)]/60"
              >
                <div className="mb-3 flex flex-col gap-3 sm:flex-row sm:items-center sm:justify-between">
                  <div className="min-w-0 flex-1">
                    <div className="mb-2 flex items-center gap-2">
                      <h2 className="truncate text-xl font-medium text-[var(--color-text)]" title={drive?.name}>
                        {drive?.name}
                      </h2>
                      <span className="rounded-full border border-[var(--color-border)] bg-[var(--color-surface-elevated)] px-2 py-0.5 text-xs text-[var(--color-text-muted)]">
                        {drive?.scannedFrom || 'Невідомо'}
                      </span>
                    </div>
                  </div>
                  <div className="flex w-full flex-col items-end gap-1 sm:w-[320px]">
                    <p
                      className="text-right text-[10px] text-[var(--color-text-muted)]/55 sm:whitespace-nowrap"
                      title={drive?.scannedAt ? formatDate(drive.scannedAt) : '—'}
                    >
                      Останнє сканування: {drive?.scannedAt ? formatDate(drive.scannedAt) : '—'}
                    </p>
                    <div className="flex w-full items-center gap-3">
                      <div className="h-2 w-full overflow-hidden rounded-full bg-[var(--color-surface-elevated)]">
                        <div
                          className={`h-full rounded-full ${getUsageColorClass(usagePercent)}`}
                          style={{ width: `${usagePercent}%` }}
                        />
                      </div>
                      <span className="w-11 shrink-0 text-right text-xs text-[var(--color-text-muted)]">
                        {usagePercent}%
                      </span>
                    </div>
                  </div>
                </div>

                <div className="mt-2 flex flex-wrap items-center justify-between gap-3">
                  <p className="text-sm text-[var(--color-text-muted)]">
                    {foldersCount} {pluralizeUk(foldersCount, ['папка', 'папки', 'папок'])}, {filesCount}{' '}
                    {pluralizeUk(filesCount, ['файл', 'файли', 'файлів'])}
                  </p>
                  <p className="text-right text-sm font-medium text-[var(--color-text)]">
                    {formatBytes(usedBytes)} / {formatBytes(totalBytes)}
                  </p>
                </div>

                {normalizedQuery ? (
                  <div className="mt-4 rounded-xl border border-[var(--color-border)] bg-[var(--color-surface-elevated)] p-3">
                    <p className="mb-2 text-xs font-medium uppercase tracking-wide text-[var(--color-text-muted)]">Збіги:</p>
                    <div className="space-y-1">
                      {matches.map((entry, index) => (
                        <div key={`${entry?.name}-${index}`} className="flex items-center justify-between gap-2">
                          <p className="min-w-0 truncate text-sm text-[var(--color-text)]">
                            <EntryIcon type={entry?.type} /> {highlightText(String(entry?.name || ''), normalizedQuery)}
                          </p>
                          <p className="shrink-0 text-xs text-[var(--color-text-muted)]">
                            {formatBytes(entry?.sizeBytes || 0)}
                          </p>
                        </div>
                      ))}
                    </div>
                  </div>
                ) : null}

                {isExpanded ? (
                  <div className="mt-4 border-t border-[var(--color-border)] pt-4">
                    <div className="space-y-2">
                      {detailEntries.map((entry, index) => {
                        const isMatched = normalizedQuery && entryMatchesQuery(entry, normalizedQuery)
                        return (
                          <div
                            key={`${entry?.name}-${index}`}
                            className={`rounded-lg border px-3 py-2 text-sm transition ${
                              isMatched
                                ? 'border-[var(--color-accent)]/60 bg-[var(--color-accent)]/10'
                                : 'border-[var(--color-border)] bg-[var(--color-surface-elevated)]'
                            }`}
                          >
                            <div className="flex items-center justify-between gap-3">
                              <p className="truncate text-[var(--color-text)]">
                                <EntryIcon type={entry?.type} />{' '}
                                {highlightText(String(entry?.name || ''), normalizedQuery)}
                              </p>
                              <p className="shrink-0 text-right text-xs text-[var(--color-text-muted)]">
                                {formatBytes(entry?.sizeBytes || 0)}
                              </p>
                            </div>
                          </div>
                        )
                      })}
                    </div>
                  </div>
                ) : null}
              </article>
            )
          })}
        </section>
      ) : null}
    </div>
  )
}

export default App
