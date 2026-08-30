const fs = require('fs')
const path = require('path')

const dir = 'c:/Users/Admin/Desktop/Projects/manavizha-mobileapp/lib'
const files = fs.readdirSync(dir).filter(f => f.endsWith('.dart') && f !== 'premium_utils.dart')

for (const file of files) {
  const fp = path.join(dir, file)
  let content = fs.readFileSync(fp, 'utf8')
  let changed = false

  if (content.includes('is_premium')) {
    // 1. Add premium_expires_at to select queries
    const selectRegex = /\.select\((['"])([^'"]*is_premium[^'"]*)\1\)/g
    content = content.replace(selectRegex, (match, quote, cols) => {
      if (!cols.includes('premium_expires_at')) {
        changed = true
        return `.select(${quote}${cols}, premium_expires_at${quote})`
      }
      return match
    })
    
    // 1b. Fix safeIn select
    const safeInRegex = /safeIn\('user_settings',\s*(['"])([^'"]*is_premium[^'"]*)\1/g
    content = content.replace(safeInRegex, (match, quote, cols) => {
      if (!cols.includes('premium_expires_at')) {
        changed = true
        return `safeIn('user_settings', ${quote}${cols}, premium_expires_at${quote}`
      }
      return match
    })

    // 2. Replace == true checks with isPremiumActive
    const trueChecks = [
      /([\w_]+)(\?|)\[['"]is_premium['"]\]\s*==\s*true/g,
      /([\w_]+)\?\.\s*is_premium\s*==\s*true/g // if any
    ]
    for (const regex of trueChecks) {
      content = content.replace(regex, (match, varName) => {
        changed = true
        return `isPremiumActive(${varName})`
      })
    }

    if (changed) {
      if (!content.includes('premium_utils.dart')) {
        const importLines = content.match(/^import .*;$/gm) || []
        if (importLines.length > 0) {
          const lastImport = importLines[importLines.length - 1]
          content = content.replace(lastImport, lastImport + "\nimport 'premium_utils.dart';")
        } else {
          content = "import 'premium_utils.dart';\n" + content
        }
      }
      fs.writeFileSync(fp, content)
      console.log(`Updated ${file}`)
    }
  }
}
