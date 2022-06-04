import Path from "node:path"
import * as Text from "@dashkite/joy/text"
import * as Time from "@dashkite/joy/time"
import { 
  putItem 
  deleteItem
  scan
} from "@dashkite/dolores/graphene-alpha"
import { getPackage } from "./helpers"
import { diff } from "./diff"

export default ( genie, options ) ->

  # TODO presently unused
  { module } = options

  genie.define "sky:module:publish", [ "build" ], ->

    # the dashkite internals database
    database = "bkqooszc5jqsoyxrcedr6lrsc"
    
    collection = "modules.dashkite.com"
    
    { name, exports } = await getPackage()
    if Text.startsWith "@" then name = name[1..]
    root = Path.dirname exports["."].browser

    publish =
      root: root
      target: Path.join name, root
      encoding: "utf8"

    # Give the FS operations a sec
    await Time.sleep 1000

    # adapted from graphene-alpha code
    # TODO possibly refactor into common function(s)?

    console.log "publishing module [ #{name} ]"
    diff publish,
      list: -> 
        ( await scan { database, collection } )
          .list
          .map ({ _ }) -> _            
      add: (key, content) -> 
        console.log "... add [ #{ key } ]"
        putItem { database, collection, key, content }
      update: (key, content) ->
        console.log "... update [ #{ key } ]"
        putItem { database, collection, key, content }
      delete: (key) ->
        console.log "... delete [ #{ key } ]"
        deleteItem { database, collection, key }