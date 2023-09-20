import { inspect } from "node:util"
import Path from "node:path"
import Zephyr from "@dashkite/zephyr"
import { log } from "@dashkite/dolores/logger"
import * as Graphene from "@dashkite/graphene-core"
import * as Polaris from "@dashkite/polaris"
import { yaml, getDRN, getDomain } from "@dashkite/drn"
import { diff } from "#helpers/diff"

resolveTables = ( tables ) ->
  resolved = {}
  for key, value of tables
    resolved[ key ] = await getDRN value
  resolved

Sky =
  root: Path.join "#{ process.env.HOME }", ".sky"
  path: ( name ) -> Path.join @root, "#{ name }.yaml"
  read: ( name ) -> Zephyr.read @path name
  write: ( name, data ) -> Zephyr.write ( @path name ), data

Tasks =

  deploy: ({ graphene })  ->
    client = Graphene.Client.create 
      tables: await resolveTables graphene.tables
    created = {}
    for db in graphene.databases
      name = await getDRN db.uri
      address = undefined
      byname = undefined
      if ( data = await Sky.read name )?
        { address } = data
        log "graphene", "deploy", 
          "found db: #{ address } for: #{ name }."
      else
        { address } = await client.db.create { name }
        log "graphene", "deploy", 
          "created db: #{ address } for: #{ name }."
        await Sky.write name, { address }
      
      created[ address ] = []
      for collection in db.collections
        { byname, bynames, uri } = collection
        byname ?= bynames?[ name ] ?
          ( if uri? then await getDomain uri )
        if byname?
          await do ( byname ) ->
            do ({ db, collection } = {}) ->
              db = client.db address
              if !( collection = await db.collection.get byname )?
                collection = await db.collection.create { byname }
                log "graphene", "deploy", "created collection: 
                  #{ byname } for database: #{ address }"
                created[ address ].push byname
    Promise.all do ->
      for address, bynames of created 
        for byname in bynames
          do ({ db, response } = {}) ->
            db = client.db address
            loop
              response = await db.collection.getStatus byname
              break if response.status == "ready"
              await Time.sleep 1000

  publish: ({ graphene }) ->
    client = Graphene.Client.create tables: await resolveTables graphene.tables
    for db in graphene.databases
      for collection in db.collections when collection.publish?
        name = await getDRN db.uri
        { publish, byname } = collection
        if !byname?
          byname = collection.bynames[ name ]
        _collection = client.collection { 
          db: db.addresses[ name ]
          collection: byname 
        }
        publish.encoding ?= "utf8"
        log "graphene", "publish", "publishing collection: #{byname} for database: #{db.addresses[ drn ]}."
        diff publish,
          list: -> _collection.metadata.list()
          add: (key, content) -> 
            log "graphene", "publish", "entry > add", { key }
            _collection.put key, content
          update: (key, content) ->
            log "graphene", "publish", "entry > update", { key }
            _collection.put key, content
          delete: (key) ->
            log "graphene", "publish", "entry > delete", { key }
            _collection.delete key

  undeploy: ({ graphene }) ->
    client = Graphene.Client.create tables: await resolveTables graphene.tables
    updated = false
    for db in graphene.databases
      name = await getDRN db.uri
      if ( address = db.addresses[ name ])?
        await client.db.delete address
        log "graphene", "undeploy", "deleted db: 
          #{ address } for drn: #{ name }."
        delete db.addresses[ name ]
        updated = true
      for collection in db.collections
        if collection.bynames?[ name ]?
          delete collection.bynames[ name ]
          updated = true
    if updated then await updateConfig graphene

export default Tasks