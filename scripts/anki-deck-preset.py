#!/usr/bin/env python3
"""One-time: give the Lexicard deck its own Anki options preset with sibling burying on.

Recognize already comes first because new cards are sorted by card type (newSortOrder 0).
Other decks keep their presets. Reads ANKICONNECT_URLS, ANKICONNECT_API_KEY and ANKI_DECK from .env.
"""
import json
import urllib.request

env = {}
for line in open(".env", encoding="utf-8"):
    line = line.strip()
    if line and not line.startswith("#") and "=" in line:
        key, value = line.split("=", 1)
        env[key.strip()] = value.strip()
url = env["ANKICONNECT_URLS"].split(",")[0].strip()
api_key = env.get("ANKICONNECT_API_KEY", "")
deck = env.get("ANKI_DECK") or "Reading vocabulary"


def call(action, **params):
    request = {"action": action, "version": 6, "params": params}
    if api_key:
        request["key"] = api_key
    data = json.dumps(request).encode()
    req = urllib.request.Request(url, data, {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30) as response:
        reply = json.load(response)
    if reply.get("error"):
        raise SystemExit(f"{action}: {reply['error']}")
    return reply["result"]


conf = call("getDeckConfig", deck=deck)
if conf["name"] != "Lexicard":
    new_id = call("cloneDeckConfigId", name="Lexicard", cloneFrom=str(conf["id"]))
    call("setDeckConfigId", decks=[deck], configId=new_id)
    conf = call("getDeckConfig", deck=deck)
conf["new"]["bury"] = True
conf["rev"]["bury"] = True
conf["buryInterdayLearning"] = True
conf["newSortOrder"] = 0
call("saveDeckConfig", config=conf)
check = call("getDeckConfig", deck=deck)
print(f'{deck}: preset "{check["name"]}" (id {check["id"]}); bury new={check["new"]["bury"]}, '
      f'review={check["rev"]["bury"]}, interday={check["buryInterdayLearning"]}; newSortOrder={check["newSortOrder"]}')
