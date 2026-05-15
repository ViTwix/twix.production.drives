import { copyFileSync, existsSync, mkdirSync, writeFileSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'
import pngToIco from 'png-to-ico'

const __filename = fileURLToPath(import.meta.url)
const __dirname = dirname(__filename)

const sourceDir = join(__dirname, '..', '..', 'AppIcons', 'Assets.xcassets', 'AppIcon.appiconset')
const targetDir = join(__dirname, '..', 'public')

const iconMap = [
  ['180.png', 'apple-touch-icon.png'],
  ['167.png', 'apple-touch-icon-167x167.png'],
  ['152.png', 'apple-touch-icon-152x152.png'],
  ['32.png', 'favicon-32x32.png'],
  ['16.png', 'favicon-16x16.png'],
  ['256.png', 'android-chrome-256x256.png'],
  ['512.png', 'android-chrome-512x512.png'],
]

const missing = iconMap
  .map(([src]) => src)
  .filter((src) => !existsSync(join(sourceDir, src)))

if (missing.length > 0) {
  throw new Error(`Missing AppIcons assets: ${missing.join(', ')}`)
}

mkdirSync(targetDir, { recursive: true })

for (const [sourceName, targetName] of iconMap) {
  copyFileSync(join(sourceDir, sourceName), join(targetDir, targetName))
}

const icoBuffer = await pngToIco([
  join(sourceDir, '16.png'),
  join(sourceDir, '32.png'),
  join(sourceDir, '64.png'),
])
writeFileSync(join(targetDir, 'favicon.ico'), icoBuffer)
