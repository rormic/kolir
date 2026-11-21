.pragma library

// Pure search and calculator helpers for the launcher. No QML or process
// state lives here; callers pass the application list or the raw query.

function filterApplications(apps, queryText) {
    if (!apps || apps.length === 0) return []

    const q = (queryText || "").trim().toLowerCase()

    // 1. Порожній запит: показуємо всі програми
    if (q === "") {
        return apps.slice()
    }

    // 2. Пошук за запитом
    const scored = []
    for (let i = 0; i < apps.length; i++) {
        const app = apps[i]
        const name = (app.name || "").toLowerCase()
        const id = (app.id || "").toLowerCase()
        const genericName = (app.genericName || "").toLowerCase()

        let matchScore = 0

        // Перевіряємо збіги за релевантністю
        if (name === q) {
            matchScore = 1000
        } else if (name.startsWith(q)) {
            matchScore = 500
        } else {
            const words = name.split(/[\s\-_]+/)
            let wordPrefixMatch = false
            for (let w = 0; w < words.length; w++) {
                if (words[w].startsWith(q)) {
                    wordPrefixMatch = true
                    break
                }
            }

            if (wordPrefixMatch) {
                matchScore = 350
            } else if (name.includes(q)) {
                matchScore = 150
            } else if (id.startsWith(q)) {
                matchScore = 120
            } else if (id.includes(q)) {
                matchScore = 70
            } else if (genericName.startsWith(q)) {
                matchScore = 90
            } else if (genericName.includes(q)) {
                matchScore = 50
            }
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
