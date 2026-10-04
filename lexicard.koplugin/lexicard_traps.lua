--[[
Known traps for Spanish speakers: used in the prompt and by the code checks.
Sources: learner-corpus and ELT lists (see the v0.2 spec).
]]
local Text = require("lexicard_text")

local Traps = {}

-- English word → { Spanish look-alike, what to say instead }
Traps.FALSE_FRIENDS = {
    actually = { "actualmente", "en realidad" },
    actual = { "actual", "real" },
    eventually = { "eventualmente", "al final" },
    ultimately = { "últimamente", "al final" },
    realize = { "realizar", "darse cuenta" },
    embarrassed = { "embarazada", "apenado" },
    sensible = { "sensible", "sensato" },
    sympathetic = { "simpático", "comprensivo" },
    pretend = { "pretender", "fingir" },
    assist = { "asistir", "ayudar" },
    attend = { "atender", "asistir a" },
    library = { "librería", "biblioteca" },
    career = { "carrera", "profesión" },
    exit = { "éxito", "salida" },
    success = { "suceso", "éxito" },
    molest = { "molestar", "abusar de" },
    parents = { "parientes", "padres" },
    lecture = { "lectura", "conferencia" },
    large = { "largo", "grande" },
    argument = { "argumento", "discusión" },
    support = { "soportar", "apoyar" },
    record = { "recordar", "grabar" },
    deception = { "decepción", "engaño" },
    sane = { "sano", "cuerdo" },
    carpet = { "carpeta", "alfombra" },
}

-- English pairs that share one Spanish verb: { word, partner, Spanish verb, how to tell them apart, autofill }
-- Only pairs whose words have one main sense are filled in by code; the rest are left to the model.
local PAIRS = {
    { "borrow", "lend", "prestar", "borrow = pedir prestado; lend = prestar a alguien", true },
    { "say", "tell", "decir", "tell lleva a quién (tell me); say no (say hello)", true },
    { "make", "do", "hacer", "make = crear o producir; do = realizar una actividad", true },
    { "hear", "listen", "oír o escuchar", "hear = percibir un sonido; listen = prestar atención", true },
    { "rob", "steal", "robar", "rob a una persona o un lugar; steal una cosa", true },
    { "earn", "win", "ganar", "earn = ganar con trabajo; win = ganar un juego o premio", true },
    { "remember", "remind", "recordar", "remember = acordarse; remind = hacer que alguien recuerde", true },
    { "see", "watch", "ver", "see = percibir con la vista; watch = mirar con atención", false },
    { "bring", "take", "llevar o traer", "bring = hacia donde estás; take = hacia otro lugar", false },
    { "miss", "lose", "perder", "miss = perder un bus o una oportunidad; lose = perder un objeto o un juego", false },
}

Traps.CONFUSABLES = {}
for _, p in ipairs(PAIRS) do
    if p[5] then
        Traps.CONFUSABLES[p[1]] = { partner = p[2], spanish = p[3], note = p[4] }
        Traps.CONFUSABLES[p[2]] = { partner = p[1], spanish = p[3], note = p[4] }
    end
end

function Traps.confusable_warning(headword)
    local entry = Traps.CONFUSABLES[Text.fold(headword)]
    if not entry then return nil end
    return ("En español ambos son «%s»: %s"):format(entry.spanish, entry.note)
end

Traps.PREPOSITION_ERRORS = {
    "*depend of → depend on", "*married with → married to", "*think in → think of/about",
    "*dream with → dream of", "*consist in → consist of", "*enter in → enter", "*wait the bus → wait for the bus",
    "*look the man → look at the man", "*listen him → listen to him", "*good in → good at",
    "*in love of → in love with", "*help to my friends → help my friends", "*explain me → explain to me",
    "*arrive to → arrive at/in", "*discuss about → discuss", "*I have 20 years → I'm 20",
    "*lose the bus → miss the bus", "*I am agree → I agree",
}

Traps.SOUNDS = {
    { "v_b", "/v/ is not /b/: very /ˈvɛri/" },
    { "short_i", "/ɪ/ is not /i/: ship /ʃɪp/, sheep /ʃip/" },
    { "vowels", "/æ/, /ʌ/ and /ɑ/ differ: cat /kæt/, cut /kʌt/, cot /kɑt/" },
    { "schwa", "weak vowel /ə/: today /təˈdeɪ/" },
    { "s_cluster", "no extra e- before s + consonant: school /skul/" },
    { "ed_ending", "-ed is /t/, /d/ or /ɪd/: walked /wɔkt/, played /pleɪd/, wanted /ˈwɑntɪd/" },
    { "z_sound", "/z/, not /s/: eyes /aɪz/" },
    { "th", "/θ/ and /ð/: think /θɪŋk/, this /ðɪs/" },
    { "j_y", "/dʒ/ is not /j/: jet /dʒɛt/, yet /jɛt/" },
    { "sh_ch", "/ʃ/ is not /tʃ/: share /ʃɛr/, chair /tʃɛr/" },
    { "h_sound", "soft /h/, not the Spanish jota: house /haʊs/" },
    { "final_cluster", "final consonant groups: next /nɛkst/" },
    { "stress", "word stress: breakfast /ˈbrɛkfəst/" },
    { "silent_letter", "silent letters: island /ˈaɪlənd/" },
}

Traps.PREPOSITIONS = {}
for w in ("of on in at to for with about from by into onto over up"):gmatch("%S+") do Traps.PREPOSITIONS[w] = true end

Traps.VULGAR = {}
for w in ("chingon chingona chingada chingar pinche cabron cabrona pedo verga culero culera pendejo pendeja mamon mamona joder puta puto mierda"):gmatch("%S+") do
    Traps.VULGAR[w] = true
end

function Traps.false_friend(headword)
    local entry = Traps.FALSE_FRIENDS[Text.fold(headword)]
    if not entry then return nil end
    return { lookalike = entry[1], say = entry[2] }
end

function Traps.false_friend_warning(headword)
    local ff = Traps.false_friend(headword)
    if not ff then return nil end
    return ("Falso amigo: ✗ «%s» → ✓ «%s»"):format(ff.lookalike, ff.say)
end

-- The reference block pasted into the system instruction.
function Traps.prompt_lists()
    local keys = {}
    for k in pairs(Traps.FALSE_FRIENDS) do keys[#keys + 1] = k end
    table.sort(keys)
    local friends = {}
    for _, k in ipairs(keys) do
        local e = Traps.FALSE_FRIENDS[k]
        friends[#friends + 1] = ("%s ≠ %s → %s"):format(k, e[1], e[2])
    end
    local pairs_text = {}
    for _, p in ipairs(PAIRS) do pairs_text[#pairs_text + 1] = ("%s/%s (%s)"):format(p[1], p[2], p[3]) end
    local lines = {
        "Known false friends (English ≠ Spanish look-alike → what to say):",
        table.concat(friends, "; "),
        "",
        "Known confusable pairs (two English words, one Spanish word; use trap \"confusable\"):",
        table.concat(pairs_text, "; "),
        "",
        "Known preposition and calque errors (* = wrong):",
        table.concat(Traps.PREPOSITION_ERRORS, "; "),
        "",
        "Sound traps (put the name in `sound`):",
    }
    for _, s in ipairs(Traps.SOUNDS) do lines[#lines + 1] = ("%s: %s"):format(s[1], s[2]) end
    return table.concat(lines, "\n")
end

return Traps
