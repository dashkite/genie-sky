import FS from "fs/promises"
import sort from "sort-package-json"
import { Messages } from "@dashkite/messages"
import catalog from "./catalog"
import { getHash } from "@dashkite/masonry/atlas"

messages = Messages.create()
messages.add catalog

guard = (f) ->
  (args...) ->
    if f.length == args.length
       f args...
    else
      fatal "missing arguments",
        expected: f.length
        got: args.length

getPackage = do (cache = null) -> ->
  cache ?= JSON.parse await FS.readFile "./package.json", "utf8"

log = ( key, context ) ->
  console.log "sky:presets: " + messages.message key, context

warn = ( key, context ) ->
  console.warn "sky:presets: " + messages.message key, context

fatal = ( key, context ) ->
  console.error "sky:presets: " + messages.message key, context

export { guard, getPackage, getHash, log, warn, fatal }