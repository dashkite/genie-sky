import { inspect } from "node:util"
import Path from "node:path"
import { log } from "@dashkite/dolores/logger"
import * as Graphene from "@dashkite/graphene-core"
import * as Polaris from "@dashkite/polaris"
import * as DRN from "@dashkite/drn-sky"
import * as Fn from "@dashkite/joy/function"
import Time from "@dashkite/joy/time"
import * as Diff from "@dashkite/diff"
import LocalStorage from "@dashkite/sky-local-storage"
import M from "@dashkite/masonry"
import W from "@dashkite/masonry-targets/watch"

resolve = ( dictionary ) ->
  resolved = {}
  for key, value of dictionary
    resolved[ key ] = await DRN.resolve value
  resolved

Client =

  make: ({ tables }) ->
    Graphene.Client.create 
      tables: await resolve tables

Log =

  DB:

    found: ({ drn, address }) ->
      log "graphene", "deploy", 
        "found db: #{ address } for: #{ drn }."

    create: ({ drn, address }) ->
      log "graphene", "deploy", 
        "Created db: #{ address } for: #{ drn }."

    undeploy: ({ drn, address }) ->
      log "graphene", "undeploy", 
        "Deleted db: #{ address } for: #{ drn }."

  Collection:

    create: ({ address, byname }) ->
      log "graphene", "deploy", "Created collection: 
        #{ byname } for database: #{ address }"

    publish: ({ address, byname }) ->
      log "graphene", "publish", 
        "publishing collection:
          #{byname} for database: #{ address }."

    action: Fn.tee ({ action, key }) ->
      log "graphene", "publish", 
        "... #{ action } [ #{ key } ]"
      undefined # avoid returning a promise

DB =
  
  resolve: ({ drn, uri }) ->
    DRN.resolve drn ? uri

  deploy: ( client, { drn, uri }) ->
    drn ?= uri
    try
      address = await DRN.resolve drn
      Log.DB.found { drn, address }
    catch error
      if error.message.startsWith "No address found"      
        { address } = await client.db.create { name }
        await DRN.store drn, { address }
        Log.DB.create { drn, address }
      else
        throw error

  delete: ( client, { drn, uri }) ->
    drn ?= uri
    address = await DRN.resolve drn
    await client.db.delete address
    await DRN.remove drn
    Log.DB.undeploy { drn, address }

Collection =

  resolve: ({ byname, drn, uri }) ->
    drn ?= uri
    if ( byname ?= await DRN.resolve drn )?
      byname
    else
      throw new Error "No byname or DRN 
        specified for collection"

  deploy: ( client, db, { byname, uri }) ->
    byname = await Collection.resolve { uri, byname }
    db = client.db await DB.resolve db
    if !( collection = await db.collection.get byname )?
      await db.collection.create { byname }
      loop
        response = await db.collection.getStatus byname
        break if response.status == "ready"
        await Time.sleep 1000
      Log.Collection.deploy { address, byname }

  publish: ( client, db, { glob, publish, collection... }) ->
    address = await DB.resolve db
    glob ?= "**"
    publish.encoding ?= "utf8"
    byname = await Collection.resolve collection
    collection = client.collection { 
      db: address
      collection: byname
    }
    Log.Collection.publish { address, byname }
    Diff.diff
      source: Diff.FS.glob publish
      target: Diff.Graphene.glob { glob, collection }
      patch: Fn.pipe [
        Log.Collection.action
        Diff.Graphene.patch { collection }
      ]

Item =

  publish: ( client, db, collection ) ->
    do ({ address, byname, _collection } = {}) ->
      ( context ) ->
        address ?= await DB.resolve db
        byname ?= await Collection.resolve collection
        _collection ?= client.collection { 
          db: address
          collection: byname
        }
        _collection.put context.source.path, context.input


  rm: ( client, db, collection ) ->
    do ({ address, byname, _collection } = {}) ->
      ( context ) ->
        address ?= await DB.resolve db
        byname ?= await Collection.resolve collection
        _collection ?= client.collection { 
          db: address
          collection: byname
        }
        _collection.delete context.source.path


Tasks =

  deploy: ({ graphene })  ->
    client = await Client.make graphene
    Promise.all await do ->
      for { collections, db... } in graphene.databases
        await DB.deploy client, db
        Promise.all do ->
          for collection in collections
            Collection.deploy client, db, collection
  
  undeploy: ({ graphene }) ->
    client = await Client.make graphene
    Promise.all do ->
      for db in graphene.databases
        DB.delete client, db

  publish: ({ graphene }) ->
    client = await Client.make graphene
    Promise.all do ->
      for { collections, db... } in graphene.databases
        Promise.all do ->
          for collection in collections
            Collection.publish client, db, collection

  watch: ({ graphene }) ->

    client = await Client.make graphene

    watch = ( db, collection ) ->
      
      do M.start [
        W.glob collection.publish
        W.match type: "file", name: [ "add", "change" ], [
          M.read
          Item.publish client, db, collection
        ]
        W.match type: "file", name: "rm", [
          Item.rm client, db, collection
        ]
      ]

    Promise.all do ->
      for { collections, db... } in graphene.databases
        Promise.all do ->
          for collection in collections
            watch db, collection


export default Tasks