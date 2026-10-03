-- Call one AnkiConnect action with the key from .env and print the result.
-- Usage: luajit scripts/anki.lua ACTION ['{"json": "params"}']
package.path = "lexicard.koplugin/?.lua;spec/support/?.lua;scripts/lib/?.lua;" .. package.path
local Anki = require("lexicard_anki")
local Config = require("lexicard_config")
local Curl = require("curl_transport")
local Json = require("lexicard_json")

local cfg = Config.load(".env")
local params = arg[2] and assert(Json.decode(arg[2]), "params must be JSON") or nil
local kind, result = Anki.call(Curl.transport, cfg.ankiconnect_urls[1], cfg, arg[1], params, 30)
print(kind, Json.encode(result))
os.exit(kind == "ok" and 0 or 1)
