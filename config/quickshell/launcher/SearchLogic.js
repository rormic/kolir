.pragma library

// Pure search and calculator helpers for the launcher. No QML or process
// state lives here; callers pass the application list or the raw query.

// ── Layout-independent search ──────────────────────────────────────────────
// A query typed while the wrong keyboard layout is active must still find the
// application it spells: "вуфвдщсл" on the Ukrainian layout is "deadlock" on
// the US one. The map is not written here: `scripts/layout-map.py` asks
// libxkbcommon for the layouts Hyprland actually has, so every language works
// without a hand-written table. Each layout arrives as a list of
// [usChar, layoutChar] pairs for the keys whose level-0 character differs from
// the US layout, and the launcher passes it to the functions below.
//
// ASCII text is taken literally: "a" is "a" whichever layout typed it, and the
// text alone cannot tell which key produced it. Only the characters a non-US
// layout adds (Cyrillic, Greek, an umlaut, …) are translated, which keeps a
// literal search exact.

// The US spelling of text typed in another layout (Cyrillic → Latin).
function toUsLayout(text, pairs) {
    if (!pairs || pairs.length === 0) return text
    let out = ""
    for (let i = 0; i < text.length; i++) {
        const ch = text.charAt(i)
        let mapped = ch
        if (ch.charCodeAt(0) > 127) {
            for (let p = 0; p < pairs.length; p++) {
                if (pairs[p][1] === ch) {
                    mapped = pairs[p][0]
                    break
                }
            }
        }
        out += mapped
    }
    return out
}

// The spelling of US text under another layout (Latin → Cyrillic).
function toLayout(text, pairs) {
    if (!pairs || pairs.length === 0) return text
    let out = ""
    for (let i = 0; i < text.length; i++) {
        const ch = text.charAt(i)
        let mapped = ch
        for (let p = 0; p < pairs.length; p++) {
            const other = pairs[p][1]
            if (pairs[p][0] === ch && other.charCodeAt(0) > 127) {
                mapped = other
                break
            }
        }
        out += mapped
    }
    return out
}

// Adds a spelling unless the literal query or an earlier layout already
// produced it. Every non-literal variant is one point cheaper than a literal
// match on purpose (see `queryVariants`).
function addVariant(variants, text) {
    if (!text) return
    for (let i = 0; i < variants.length; i++) {
        if (variants[i].text === text) return
    }
    variants.push({ text: text, penalty: 1 })
}

// Every spelling of one query the same physical keys can produce. The literal
// spelling keeps a one-point bonus, so an exact match in the active layout
// always outranks the same match reached through another layout.
function queryVariants(query, layouts) {
    const variants = [{ text: query, penalty: 0 }]
    const list = layouts || []

    for (let i = 0; i < list.length; i++) {
        const pairs = list[i] ? list[i].pairs : null
        if (!pairs || pairs.length === 0) continue
        addVariant(variants, toUsLayout(query, pairs))
        addVariant(variants, toLayout(query, pairs))
    }

    return variants
}

// One application's score for a single query spelling, or 0 for no match.
function scoreApplication(app, q) {
    const name = (app.name || "").toLowerCase()
    const id = (app.id || "").toLowerCase()
    const genericName = (app.genericName || "").toLowerCase()

    // Перевіряємо збіги за релевантністю
    if (name === q) return 1000
    if (name.startsWith(q)) return 500

    const words = name.split(/[\s\-_]+/)
    for (let w = 0; w < words.length; w++) {
        if (words[w].startsWith(q)) return 350
    }

    if (name.includes(q)) return 150
    if (id.startsWith(q)) return 120
    if (id.includes(q)) return 70
    if (genericName.startsWith(q)) return 90
    if (genericName.includes(q)) return 50
    return 0
}

function filterApplications(apps, queryText, layouts) {
    if (!apps || apps.length === 0) return []

    const q = (queryText || "").trim().toLowerCase()

    // 1. Порожній запит: показуємо всі програми
    if (q === "") {
        return apps.slice()
    }

    // 2. Пошук за запитом у кожній розкладці
    const variants = queryVariants(q, layouts)
    const scored = []
    for (let i = 0; i < apps.length; i++) {
        const app = apps[i]

        let matchScore = 0
        for (let v = 0; v < variants.length; v++) {
            const variantScore = scoreApplication(app, variants[v].text)
            if (variantScore <= 0) continue
            const adjusted = variantScore - variants[v].penalty
            if (adjusted > matchScore) matchScore = adjusted
        }

        if (matchScore > 0) {
            scored.push({
                app: app,
                score: matchScore,
                name: app.name || ""
            })
        }
    }

    // Сортуємо за найвищим балом; при рівності — за алфавітом
    scored.sort((a, b) => {
        if (b.score !== a.score) return b.score - a.score
        return a.name.localeCompare(b.name)
    })

    return scored.map(item => item.app)
}

// True when the text contains the query in any layout spelling. The clipboard
// filter uses it so a wrong-layout query still finds the copied text.
function matchesText(text, queryText, layouts) {
    const haystack = (text || "").toLowerCase()
    const q = (queryText || "").trim().toLowerCase()
    if (q === "") return true

    const variants = queryVariants(q, layouts)
    for (let i = 0; i < variants.length; i++) {
        if (haystack.indexOf(variants[i].text) !== -1) return true
    }
    return false
}

// Безпечна функція математичного калькулятора
function evalMath(input) {
    if (!input) return null
    let s = input.trim()
    if (s.startsWith("=")) {
        s = s.substring(1).trim()
    }
    if (s === "") return null

    // Ігноруємо якщо це режим буфера обміну (починається з ;)
    if (s.startsWith(";")) return null

    // Має містити математичні оператори або починатися з =
    const hasOp = /[\+\-\*\/\%\^]/.test(s)
    if (!hasOp && !input.trim().startsWith("=")) return null

    // Дозволені тільки цифри, пробіли, крапка, оператори та дужки
    if (!/^[\d\s\+\-\*\/\%\^\(\)\.]+$/.test(s)) return null

    // Обов'язкова наявність хоча б однієї цифри
    if (!/\d/.test(s)) return null

    // Не обчислюємо незавершені вирази з оператором на кінці (наприклад, "2 +")
    if (/[\+\-\*\/\%\^]\s*$/.test(s)) return null

    try {
        let expr = s.replace(/\^/g, "**")
        const res = Function('"use strict"; return (' + expr + ')')()
        if (typeof res === "number" && !isNaN(res) && isFinite(res)) {
            let formatted = parseFloat(res.toPrecision(12)).toString()
            return {
                expr: s,
                result: formatted,
                num: res
            }
        }
    } catch (e) {
        return null
    }
    return null
}
