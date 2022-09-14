import Path from "node:path"
import * as Text from "@dashkite/joy/text"
import * as Time from "@dashkite/joy/time"
import * as Graphene from "@dashkite/graphene-lambda-client"
import { getPackage } from "./helpers"
import { diff } from "./diff"

export default ( genie, options ) ->

  client = Graphene.Client.create "graphene-beta-development-api"

  # TODO presently unused
  { module } = options

  genie.define "sky:module:publish", [ "build" ], ->

    # the dashkite internals database
    db = await client.db.get "dd343rnxc1hjqqhu0hq8viun7"
    collection = await db.collections.get "modules.dashkite.com"
    
    { name, exports } = await getPackage()
    if Text.startsWith "@" then name = name[1..]
    root = Path.dirname exports["."].browser

    publish =
      root: root
      target: Path.join name, root
      encoding: "utf8"

    # Give the FS operations a sec
    await Time.sleep 1000

    # TODO possibly refactor into common function(s)?

    console.log "publishing module [ #{name} ]"
    diff publish,
      list: -> collection.metadata.list()      
      add: (key, content) -> 
        console.log "... add [ #{ key } ]"
        collection.entries.put key, content
      update: (key, content) ->
        console.log "... update [ #{ key } ]"
        collection.entries.put key, content
      delete: (key) ->
        console.log "... delete [ #{ key } ]"
        collection.entries.delete key