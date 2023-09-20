import FS from "fs/promises"
import { log } from "@dashkite/dolores/logger"
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

warn = ( key, context ) ->
  log "genie-sky", "info", messages.message key, context

warn = ( key, context ) ->
  log "genie-sky", "warn", messages.message key, context

fatal = ( key, context ) ->
  log "genie-sky", "fatal", messages.message key, context

export { 
  getPackage, 
  info, warn, fatal
}