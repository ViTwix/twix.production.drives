import { useEffect, useMemo, useState } from 'react'
import { formatBytes, formatDate, pluralizeUk } from './lib/format'
import { driveMatchesQuery, entryMatchesQuery, getTopMatches, normalizeQuery } from './lib/search'

const DATA_URL =
  'https://raw.githubusercontent.com/ViTwix/twix.production.drives/main/data/drives.json'

const getUsageColorClass = (percent) => {
  if (percent > 90) {
    return 'bg-[var(--color-danger)]'
  }

  if (percent >= 70) {
    return 'bg-[var(--color-warn)]'
  }

  return 'bg-[var(--color-ok)]'
}

const sortBySizeDesc = (a, b) => (b?.sizeBytes || 0) - (a?.sizeBytes || 0)

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
  const [selectedDriveName, setSelectedDriveName] = useState('')
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
    return [...source].sort((a, b) => String(a?.name || '').localeCompare(String(b?.name || ''), 'uk'))
  }, [data])

  const visibleDrives = useMemo(
    () => drives.filter((drive) => driveMatchesQuery(drive, normalizedQuery)),
    [drives, normalizedQuery],
  )

  const selectedDrive = useMemo(
    () => drives.find((drive) => drive?.name === selectedDriveName) || null,
    [drives, selectedDriveName],
  )

  const detailEntries = useMemo(() => {
    if (!selectedDrive) {
      return []
    }

    const entries = Array.isArray(selectedDrive.entries) ? [...selectedDrive.entries].sort(sortBySizeDesc) : []

    if (!normalizedQuery) {
      return entries
    }

    const matched = []
    const rest = []

    for (const entry of entries) {
      if (entryMatchesQuery(entry, normalizedQuery)) {
        matched.push(entry)
      } else {
        rest.push(entry)
      }
    }

    return [...matched, ...rest]
  }, [selectedDrive, normalizedQuery])

  const handleRetry = () => setReloadKey((prev) => prev + 1)

  return (
    <div className="mx-auto min-h-screen w-full max-w-7xl px-4 py-8 sm:px-6 lg:px-8">
      <header className="mb-6 space-y-3">
        <h1 className="text-3xl font-semibold tracking-tight sm:text-4xl">Накопичувачі</h1>
        {data?.updatedAt ? (
          <p className="text-sm text-[var(--color-text-muted)]">Оновлено: {formatDate(data.updatedAt)}</p>
        ) : null}
        <input
          type="search"
          value={query}
          onChange={(event) => setQuery(event.target.value)}
          className="w-full rounded-xl border border-[var(--color-border)] bg-[var(--color-surface)] px-4 py-3 text-sm text-[var(--color-text)] outline-none transition focus:border-[var(--color-accent)]"
          placeholder="Пошук за назвою диска, папки або файла…"
        />
      </header>

      {isLoading ? (
        <section className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {[1, 2, 3].map((item) => (
            <div
              key={item}
              className="h-52 animate-pulse rounded-2xl border border-[var(--color-border)] bg-[var(--color-surface)]"
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
        <section className="grid grid-cols-1 gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {visibleDrives.map((drive) => {
            const entries = Array.isArray(drive?.entries) ? drive.entries : []
            const foldersCount = entries.filter((entry) => entry?.type === 'folder').length
            const filesCount = entries.filter((entry) => entry?.type === 'file').length
            const totalBytes = drive?.totalBytes || 0
            const usedBytes = drive?.usedBytes || 0
            const usagePercent = totalBytes > 0 ? Math.min(100, Math.round((usedBytes / totalBytes) * 100)) : 0
            const matches = getTopMatches(entries, normalizedQuery)
            const totalMatches = normalizedQuery
              ? entries.filter((entry) => entryMatchesQuery(entry, normalizedQuery)).length
              : 0

            return (
              <button
                key={drive?.name}
                type="button"
                onClick={() => setSelectedDriveName(String(drive?.name || ''))}
                className="card-surface text-left transition hover:border-[var(--color-accent)]/60"
              >
                <div className="mb-3 flex items-start justify-between gap-3">
                  <h2 className="text-xl font-medium text-[var(--color-text)]">{drive?.name}</h2>
                  <span className="rounded-full border border-[var(--color-border)] px-2 py-0.5 text-xs text-[var(--color-text-muted)]">
                    {drive?.scannedFrom || '—'}
                  </span>
                </div>

                <div className="mb-2 h-2 w-full overflow-hidden rounded-full bg-[var(--color-surface-elevated)]">
                  <div
                    className={`h-full rounded-full ${getUsageColorClass(usagePercent)}`}
                    style={{ width: `${usagePercent}%` }}
                  />
                </div>

                <p className="text-sm text-[var(--color-text)]">
                  {formatBytes(usedBytes)} / {formatBytes(totalBytes)}
                </p>
                <p className="mt-1 text-sm text-[var(--color-text-muted)]">
                  {foldersCount} {pluralizeUk(foldersCount, ['папка', 'папки', 'папок'])}, {filesCount}{' '}
                  {pluralizeUk(filesCount, ['файл', 'файли', 'файлів'])}
                </p>

                {normalizedQuery ? (
                  <div className="mt-4 rounded-lg border border-[var(--color-border)] bg-[var(--color-surface-elevated)] p-3">
                    <p className="mb-2 text-xs uppercase tracking-wide text-[var(--color-text-muted)]">Збіги:</p>
                    <div className="space-y-1">
                      {matches.map((entry, index) => (
                        <p key={`${entry?.name}-${index}`} className="truncate text-sm text-[var(--color-text)]">
                          {entry?.type === 'folder' ? '📁' : '📄'} {entry?.name} {formatBytes(entry?.sizeBytes || 0)}
                        </p>
                      ))}
                      {totalMatches > matches.length ? (
                        <p className="text-xs text-[var(--color-text-muted)]">
                          + ще {totalMatches - matches.length} збігів
                        </p>
                      ) : null}
                    </div>
                  </div>
                ) : null}

                <p className="mt-4 text-xs text-[var(--color-text-muted)]">
                  Останнє сканування: {drive?.scannedAt ? formatDate(drive.scannedAt) : '—'}
                </p>
              </button>
            )
          })}
        </section>
      ) : null}

      {selectedDrive ? (
        <div className="fixed inset-0 z-20 bg-black/50 p-0 sm:p-4" onClick={() => setSelectedDriveName('')}>
          <aside
            className="ml-auto h-full w-full overflow-y-auto border-l border-[var(--color-border)] bg-[var(--color-surface)] p-4 sm:max-w-[480px] sm:rounded-2xl sm:border"
            onClick={(event) => event.stopPropagation()}
          >
            <button
              type="button"
              onClick={() => setSelectedDriveName('')}
              className="mb-4 text-sm text-[var(--color-text-muted)] transition hover:text-[var(--color-text)]"
            >
              ← Назад
            </button>
            <h3 className="text-2xl font-semibold text-[var(--color-text)]">{selectedDrive.name}</h3>
            <p className="mt-1 text-sm text-[var(--color-text-muted)]">За розміром ↓</p>

            <div className="mt-4 space-y-2">
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
                    <p className="truncate text-[var(--color-text)]">
                      {entry?.type === 'folder' ? '📁' : '📄'}{' '}
                      {highlightText(String(entry?.name || ''), normalizedQuery)}
                    </p>
                    <p className="text-xs text-[var(--color-text-muted)]">{formatBytes(entry?.sizeBytes || 0)}</p>
                  </div>
                )
              })}
            </div>
          </aside>
        </div>
      ) : null}
    </div>
  )
}

export default App
