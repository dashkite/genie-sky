import { inspect } from "node:util"
import * as Graphene from "@dashkite/graphene-core"
import { guard, log, warn, fatal } from "./helpers"
import { diff } from "./diff"

export default ( genie, { graphene } ) ->
  
  client = Graphene.Client.create()

  findDB = ( name ) ->
    graphene.find ( description ) -> description.name == name

  guardDB = (f) ->
    guard ( name ) ->
      if ( description = findDB name )?
        f description
      else
        fatal "graphene db > missing configuration", { name }

  findMissing = ({ db, collections }) ->
    missing = []

    for description in collections
      if !( collection = await (client.db db).collection.get description.byname )?
        missing.push description    
    missing

  findCollection = ( cname, byname ) ->
    { db, collections } = findDB cname
    if ( description = collections.find ( collection ) -> collection.byname == byname )?
      { db, description... }
    else
      warn "graphene collection > missing configuration", { byname }

  guardCollection = (f) ->
    guard ( cname, byname ) ->
      if ( description = await findCollection cname, byname )?
        f description


  genie.define "sky:graphene:db:create", guard ( name ) ->
    { address } = await client.db.create { name }
    log "graphene db > create successful", { name, address }

  # genie.define "sky:graphene:database:delete", guard ( name ) ->

  genie.define "sky:graphene:collections:check", guardDB ( description ) ->
    missing = await findMissing description
    for { byname } in missing
      warn "graphene collection > does not exist", { byname }

  genie.define "sky:graphene:collections:put", guardDB ( description ) ->
    { db } = description
    missing = await findMissing description 
    for { name, byname } in missing
      collection = await (client.db db).collection.create { byname, name }
      log "graphene collection > create successful", { byname }

  genie.define "sky:graphene:collection:put", guardCollection ({ db, byname }) ->
    await (client.db db).collection.create { byname }
    log "graphene collection > create successful", { byname }

  genie.define "sky:graphene:collection:delete", guardCollection ({ db, byname }) ->
    await (client.db db).collection.delete byname
    log "graphene collection > delete successful", { byname }
    
  genie.define "sky:graphene:collection:publish", guardCollection ({ db, byname, publish }) ->
    collection = client.collection { db, collection: byname }
    publish.encoding ?= "utf8"
    log "graphene collection > publish", { byname }
    diff publish,
      list: -> collection.metadata.list()
      add: (key, content) -> 
        log "graphene entry > add", { key }
        collection.put key, content
      update: (key, content) ->
        log "graphene entry > update", { key }
        collection.put key, content
      delete: (key) ->
        log "graphene entry > delete", { key }
        collection.delete key
