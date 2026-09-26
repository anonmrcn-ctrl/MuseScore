// SPDX-License-Identifier: GPL-3.0-only
// Coordinates are offsets in staff spaces from a persistent musical anchor.
var FORMAT = "musescore-review-2"
var counter = 0

function empty(scoreId) { return { format: FORMAT, scoreId: scoreId, marks: [] } }
function copy(value) { return JSON.parse(JSON.stringify(value)) }
function validNumber(value) { return typeof value === "number" && Number.isFinite(value) && Math.abs(value) < 1000000 }
function validate(document, scoreId) {
    if (!document || document.format !== FORMAT)
        throw new Error("Formato di revisione non supportato; il file originale non è stato modificato.")
    if (typeof document.scoreId !== "string" || document.scoreId !== scoreId)
        throw new Error("Questa revisione appartiene a un altro spartito o a un'altra parte.")
    if (!Array.isArray(document.marks) || document.marks.length > 10000)
        throw new Error("Elenco delle annotazioni non valido.")
    var ids = {}, total = 0
    for (var i = 0; i < document.marks.length; ++i) {
        var m = document.marks[i]
        if (!m || typeof m.id !== "string" || !m.id || ids[m.id]
            || ["stroke", "text"].indexOf(m.type) < 0
            || ["draft", "print", "archive"].indexOf(m.status) < 0)
            throw new Error("Annotazione non valida.")
        ids[m.id] = true
        var a = m.anchor
        if (!a || typeof a.measure !== "string" || !a.measure || typeof a.staff !== "string" || !a.staff
            || typeof a.beat !== "string" || !validNumber(a.fraction))
            throw new Error("Riferimento musicale non valido.")
        if (!Array.isArray(m.points) || !m.points.length || m.points.length > 100000)
            throw new Error("Tratto non valido.")
        total += m.points.length
        if (total > 200000) throw new Error("La revisione contiene troppi punti.")
        for (var j = 0; j < m.points.length; ++j) {
            if (!validNumber(m.points[j].x) || !validNumber(m.points[j].y))
                throw new Error("Coordinate non valide.")
        }
        if (m.type === "text" && (typeof m.text !== "string" || m.text.length > 10000))
            throw new Error("Testo non valido.")
    }
    return document
}
function decode(json, scoreId) {
    if (json.length > 16 * 1024 * 1024) throw new Error("File di revisione troppo grande.")
    return validate(JSON.parse(json), scoreId)
}
function offset(geometry, scorePoint) {
    return { x: (scorePoint.x - geometry.x) / geometry.spatium,
             y: (scorePoint.y - geometry.y) / geometry.spatium }
}
function makeMark(type, geometry, scorePoint, text) {
    if (!geometry.valid || !(geometry.spatium > 0)) throw new Error("Nessun riferimento musicale valido.")
    return { id: Date.now().toString(36) + "-" + (++counter).toString(36), type: type,
             status: "draft", anchor: copy(geometry.anchor),
             points: [offset(geometry, scorePoint)], text: text || "" }
}
function projected(mark, geometry) {
    if (!geometry.valid) return []
    return mark.points.map(function(p) {
        return { x: geometry.x + p.x * geometry.spatium, y: geometry.y + p.y * geometry.spatium }
    })
}
function relocate(mark, geometry, scorePoint) {
    var result = copy(mark), first = result.points[0], destination = offset(geometry, scorePoint)
    result.points = result.points.map(function(p) {
        return { x: p.x - first.x + destination.x, y: p.y - first.y + destination.y }
    })
    result.anchor = copy(geometry.anchor)
    return result
}
function acceptDrafts(document, disposition) {
    if (["print", "archive"].indexOf(disposition) < 0) throw new Error("Destinazione non valida.")
    var result = copy(document)
    result.marks.forEach(function(m) { if (m.status === "draft") m.status = disposition })
    return result
}
function discardDrafts(document) {
    var result = copy(document)
    result.marks = result.marks.filter(function(m) { return m.status !== "draft" })
    return result
}
