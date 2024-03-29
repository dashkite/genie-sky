import FS from "fs/promises"
import { Messages } from "@dashkite/messages"
import catalog from "./catalog"

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

export { 
  guard, getPackage, log, 
  warn, fatal
}