import Path from "node:path"
import * as Text from "@dashkite/joy/text"
import * as Time from "@dashkite/joy/time"
import * as Graphene from "@dashkite/graphene-core"
import { getPackage, getHash } from "./helpers"
import { diff } from "./diff"

export default ( genie, options ) ->

  client = Graphene.Client.create()

  # TODO presently unused
  { module } = options

  genie.define "sky:module:publish", [ "build" ], ->

    # the dashkite internals database
    db = client.db "7tro1s4qcwnz2ytrj1eox8y1a"
    if !(collectionInstance = await db.collection.get "modules.dashkite.com")?
      collectionInstance = await db.collection.create byname: "modules.dashkite.com"
      loop
        response = await db.collection.getStatus "modules.dashkite.com"
        break if response.status == "ready"
        await Time.sleep 3 * 1000
    collection = collectionInstance.entries
    
    { name, exports } = await getPackage()
    if Text.startsWith "@" then name = name[1..]
    root = Path.dirname exports["."].browser
    hash = await getHash process.cwd()
    console.log {root, hash}

    publish =
      root: root
      target: Path.join name, hash, root
      encoding: "utf8"

    # Give the FS operations a sec
    await Time.sleep 1000

    # TODO possibly refactor into common function(s)?

    diff publish,
      list: -> collection.metadata.list()
      add: (key, content) -> 
        # console.log "... add [ #{ key } ]"
        collection.put key, content
      update: (key, content) ->
        # console.log "... update [ #{ key } ]"
        collection.put key, content
      delete: (key) ->
        # console.log "... delete [ #{ key } ]"
        collection.delete key