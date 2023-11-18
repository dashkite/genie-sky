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
import { File, Module } from "@dashkite/masonry-module"

Log =

  Collection:

    action: Fn.tee ({ action, key }) ->
      console.log "... #{ action } [ #{ key } ]"

DB =

  resolve: ( db ) -> DRN.resolve DRN.from db.address
  
  deploy: ( client, { db }) ->
    try
      address = await DB.resolve db
      console.log "Found db [ #{ address } ] for [ #{ db.name } ]."
    catch error
      if error.message.startsWith "No address found"
        { address } = await client.db.create name: db.name
        await DRN.store ( DRN.from db.address ), { address }
        console.log "Created db [ #{ address } ] for [ #{ db.name } ]."
      else
        throw error

  delete: ( client, { db }) ->
    address = await DB.resolve db
    await client.db.delete address
    await DRN.remove DRN.from db.address
    console.log "Deleted db: [ #{ address } ] for [ #{ db.name } ]."

Collection =

  deploy: ( client, { db, collection }) ->
    do ({ byname, address } = {}) ->
      { byname } = collection
      address = await DB.resolve db
      db = client.db address
      if !( collection = await db.collection.get byname )?
        console.log "Creating collection #{ byname }
          for database #{ address }"
        await db.collection.create { byname }
        console.log "Collection #{ byname } for 
          database #{ address } created"

  patch: ( collection ) ->
    Fn.pipe [
      Fn.tee ({ action, key }) ->
        console.log "... #{ action } [ #{ key } ]"
      Diff.Graphene.patch { collection }
    ]

  publish: ( client, options ) ->
    { db, collection } = options
    { byname, glob, publish } = collection
    address = await DB.resolve db
    glob ?= "**"
    publish.encoding ?= "utf8"
    collection = client.collection { 
      db: address
      collection: byname
    }
    console.log "publishing collection:
      #{byname} for database: #{ address }."
    Diff.diff
      source: Diff.FS.glob publish
      target: Diff.Graphene.glob { glob, collection }
      patch: Collection.patch collection


Item =

  publish: ( client, { db, collection }) ->
    do ({ address  } = {}) ->
      Fn.tee ( context ) ->
        address ?= await DB.resolve db
        { byname } = collection
        collection = client.collection { 
          db: address
          collection: byname
        }
        collection.put context.source.path, context.input


  rm: ( client, { db, collection }) ->
    do ({ address } = {}) ->
      Fn.tee ( context ) ->
        address ?= await DB.resolve db
        { byname } = collection
        collection = client.collection { 
          db: address
          collection: byname
        }
        collection.delete context.source.path

Tasks =

  deploy: ({ graphene })  ->
    client = await Graphene.Client.create graphene
    Promise.all await do ->
      for { collections, db... } in graphene.databases
        await DB.deploy client, { db }
        Promise.all do ->
          for collection in collections              
            Collection.deploy client, { db, collection }
  
  undeploy: ({ graphene }) ->
    client = await Graphene.Client.create graphene
    Promise.all do ->
      for db in graphene.databases
        DB.delete client, { db }

  publish: ({ graphene }) ->
    client = await Graphene.Client.create graphene
    Promise.all do ->
      for { collections, db... } in graphene.databases
        Promise.all do ->
          for collection in collections
            Collection.publish client, { db, collection }

  watch: ({ graphene }) ->
  
    W = await import( "@dashkite/masonry-watch" )

    client = await Graphene.Client.create graphene

    watch = ( db, collection ) ->
      
      do M.start [
        W.glob collection.publish
        W.match type: "file", name: [ "add", "change" ], [
          M.read
          File.hash
          File.changed Fn.flow [
            Module.data
            Item.publish client, { db, collection }
            File.stamp
            W.notify
          ]
        ]
        W.match type: "file", name: "rm", [
          File.evict
          Item.rm client, { db, collection }
        ]
      ]

    Promise.all do ->
      for { collections, db... } in graphene.databases
        Promise.all do ->
          for collection in collections
            watch db, collection


export default Tasks