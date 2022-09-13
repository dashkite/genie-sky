import { inspect } from "node:util"
import * as Graphene from "@dashkite/graphene-lambda-client"
import { guard, log, warn, fatal } from "./helpers"
import { diff } from "./diff"

export default ( genie, { graphene } ) ->
  
  client = Graphene.Client.create "graphene-beta-development-api"

  findDB = ( name ) ->
    graphene.find ( description ) -> description.name == name

  guardDB = (f) ->
    guard ( name ) ->
      if ( description = findDB name )?
        f description
      else
        fatal "graphene db > missing configuration", { name }

  findMissing = ({ db, collections }) ->
    db = await client.db.get db 
    missing = []

    for description in collections
      if !( collection = await db.collections.get description.byname )?
        missing.push description    
    { db, missing }

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
    { missing } = await findMissing description
    for { byname } in missing
      warn "graphene collection > does not exist", { byname  }

  genie.define "sky:graphene:collections:put", guardDB ( description ) ->
    { db, missing } = await findMissing description 
    for { name, byname } in missing
      collection = await db.collections.create byname, { name }
      log "graphene collection > create successful", { byname }

  genie.define "sky:graphene:collection:put", guardCollection ({ db, byname, name }) ->
    name ?= byname
    db = await client.db.get db 
    await db.collections.create byname, { name }
    log "graphene collection > create successful", { byname }

  genie.define "sky:graphene:collection:put", guardCollection ({ db, byname }) ->
    db = await client.db.get db 
    console.log inspect await db.collections.get byname

  # genie.define "sky:graphene:collection:delete", guardCollection ({ byname }) ->
    
  genie.define "sky:graphene:collection:publish", guardCollection ({ db, byname, publish }) ->
    db = await client.db.get db 
    collection = await db.collections.get byname
    publish.encoding ?= "utf8"
    log "graphene collection > publish", { byname }
    diff publish,
      list: -> ( await collection.metadata.list() ).entries
      add: (key, content) -> 
        log "graphene entry > add", { key }
        collection.entries.put key, content
      update: (key, content) ->
        log "graphene entry > update", { key }
        collection.entries.put key, content
      delete: (key) ->
        log "graphene entry > delete", { key }
        collection.entries.delete key
