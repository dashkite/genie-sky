
import { 
  createDatabase
  getCollection
  publishCollection
  putItem 
  deleteItem
  scan
} from "@dashkite/dolores/graphene-alpha"
import { guard as _guard } from "./helpers"
import { diff } from "./diff"

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
      if !( config = graphene.collections.find (c) -> c.byname == byname )?
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

    genie.define "sky:graphene:collection:delete", guard (byname) ->
      await deleteCollection { database, byname }
      console.log "deleted collection [#{byname}]" 
      

    genie.define "sky:graphene:items:publish", guard (collection) ->
      { publish } = find collection
      console.log "publishing to collection [ #{collection} ]"
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