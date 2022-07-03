import Path from "node:path"
import * as m from "@dashkite/masonry"
import * as Fn from "@dashkite/joy/function"
import * as It from "@dashkite/joy/iterable"
import * as K from "@dashkite/katana/sync"
import { guard as _guard } from "./helpers"
import { 
  createDatabase
  deleteDatabase
  getCollection
  publishCollection
  deleteCollection
  putItem 
} from "@dashkite/dolores/graphene-alpha"

export default ( genie, { graphene } ) ->
  database = null

  genie.define "sky:graphene:database:create", (name) ->
    database = await createDatabase { name }
    console.log "database successfully created. address: #{database.address}"

  genie.define "sky:graphene:database:delete", _guard (address) ->
    await deleteDatabase { address }

  if graphene?
    guard = (f) ->
      if !( database = graphene.address )?
        throw new Error "sky:graphene no address is specified"
      if !graphene.collections?
        throw new Error "sky:graphne no collections are specified"
      
      for collection, i in graphene.collections
        graphene.collections[i] = Object.assign {}, collection, { database }
      
      _guard f

    find = (byname) ->
      if ( config = graphene.collections.find (c) -> c.byname == byname )?
        throw new Error "sky:graphene collection #{byname} is not specified"
      else
        config


    genie.define "sky:graphene:collections:check", guard ->
      missing = []
      for config in graphene.collections
        if !( collection = await getCollection config )?
          missing.push config.byname

      if missing.length > 0
        for name in missing
          console.warn "Collection [#{name}] does not exist"
        throw new Error "collections:check failed"

    genie.define "sky:graphene:collections:put", guard ->
      missing = []
      for config in graphene.collections
        if !( collection = await getCollection config )?
          missing.push config

      if missing.length > 0
        for config in missing
          try
            await publishCollection config
            console.log "published collection [#{config.byname}]"
          catch error
            # we're okay if one of these fails
            console.error error.message

    genie.define "sky:graphene:collection:put", guard (byname) ->
      config = find byname
      await publishCollection config
      console.log "published collection [#{config.byname}]"

    genie.define "sky:graphene:collection:get", guard (byname) ->
      console.log await getCollection { database, byname }

    genie.define "sky:graphene:collection:delete", guard ( byname ) ->
      await deleteCollection { database, byname }
      console.log "deleted collection [#{ byname }]"

    genie.define "sky:graphene:collections:delete", ->
      for { byname } in graphene.collections
        await deleteCollection { database, byname }
        console.log "deleted collection [#{ byname }]" 
      

    genie.define "sky:graphene:items:publish", guard (byname) ->
      { publish } = find byname

      do m.start [
        m.glob ( publish?.glob ? "**/*" ), ( publish?.root ? "." )
        m.read
        It.map Fn.flow [
          K.read "input"
          K.read "source"
          K.push ( source, input ) ->
            console.log "publishing [ #{source.path} ] ..."
            collection: byname
            key: do ->
              if publish?.target?
                Path.join publish.target, source.path
              else 
                source.path
            content: input
          K.peek ({ collection, key, content }) ->
            putItem { database, collection, key, content }
        ]
      ]