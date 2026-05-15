const BYTE_UNITS = ['Б', 'КБ', 'МБ', 'ГБ', 'ТБ']

export const formatBytes = (bytes) => {
  const safeBytes = Number.isFinite(bytes) && bytes >= 0 ? bytes : 0

  if (safeBytes < 1024) {
    return `${safeBytes} Б`
  }

  const unitIndex = Math.min(
    Math.floor(Math.log(safeBytes) / Math.log(1024)),
    BYTE_UNITS.length - 1,
  )
  const value = safeBytes / 1024 ** unitIndex
  const fractionDigits = value < 10 ? 1 : 0

  return `${new Intl.NumberFormat('uk-UA', {
    minimumFractionDigits: fractionDigits,
    maximumFractionDigits: fractionDigits,
  }).format(value)} ${BYTE_UNITS[unitIndex]}`
}

export const formatDate = (iso) => {
  if (!iso) {
    return ''
  }

  return new Intl.DateTimeFormat('uk-UA', {
    year: 'numeric',
    month: '2-digit',
    day: '2-digit',
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  }).format(new Date(iso))
}

export const pluralizeUk = (n, forms) => {
  const absValue = Math.abs(Number(n) || 0)
  const mod100 = absValue % 100
  const mod10 = absValue % 10

  if (mod100 >= 11 && mod100 <= 14) {
    return forms[2]
  }

  if (mod10 === 1) {
    return forms[0]
  }

  if (mod10 >= 2 && mod10 <= 4) {
    return forms[1]
  }

  return forms[2]
}
