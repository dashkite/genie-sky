import { inspect } from "node:util"
import * as Graphene from "@dashkite/graphene-core"
import * as Polaris from "@dashkite/polaris"
import { guard, log, warn, fatal } from "./helpers"
import { yaml, getDRN, getDomain } from "@dashkite/drn"
import { diff } from "./diff"

resolveTables = ( tables ) ->
  resolved = {}
  for key, value of tables
    resolved[ key ] = await getDRN value
  resolved

export default ( genie, { graphene } ) ->
  
  updateConfig = ( config ) ->
    cfg = await yaml.read "genie.yaml"
    cfg.sky.graphene = config
    yaml.write "genie.yaml", cfg

  genie.define "sky:graphene:deploy", ->
    client = Graphene.Client.create tables: await resolveTables graphene.tables
    created = []
    updated = false
    for db in graphene.databases
      drn = await getDRN db.uri
      db.addresses ?= {}
      if !( address = db.addresses[ drn ])?
        { address } = await client.db.create { name: drn }
        console.log "created db: #{address} for drn: #{drn}."
        db.addresses[ drn ] = address
        updated = true
      for collection in db.collections
        { byname } = collection
        if !byname?
          if collection.uri?
            collection.bynames ?= {}
            if !( byname = collection.bynames[ drn ])?
              byname = await getDomain collection.uri
        if byname?
          if !( _collection = await (client.db address).collection.get byname )?
            _collection = await (client.db address).collection.create { byname }
            console.log "created collection: #{byname} for database: #{address}"
            if collection.bynames?
              collection.bynames[ drn ] = byname
            created.push { address, byname }
            updated = true
    if updated then await updateConfig graphene
    Promise.all do ->
      for { address, byname } in created 
        do ->
          loop
            response = await (client.db address).collection.getStatus byname
            break if response.status == "ready"
            await Time.sleep 3 * 1000

  genie.define "sky:graphene:publish", [ "sky:graphene:deploy" ], ->
    client = Graphene.Client.create tables: await resolveTables graphene.tables
    for db in graphene.databases
      for collection in db.collections when collection.publish?
        drn = await getDRN db.uri
        { publish, byname } = collection
        if !byname?
          byname = collection.bynames[ drn ]
        _collection = client.collection { 
          db: db.addresses[ drn ]
          collection: byname 
        }
        publish.encoding ?= "utf8"
        console.log "publishing collection: #{byname} for database: #{db.addresses[ drn ]}."
        diff publish,
          list: -> _collection.metadata.list()
          add: (key, content) -> 
            console.log "entry > add", { key }
            _collection.put key, content
          update: (key, content) ->
            console.log "entry > update", { key }
            _collection.put key, content
          delete: (key) ->
            console.log "entry > delete", { key }
            _collection.delete key

  genie.define "sky:graphene:undeploy", ->
    client = Graphene.Client.create tables: await resolveTables graphene.tables
    updated = false
    for db in graphene.databases
      drn = await getDRN db.uri
      if ( address = db.addresses[ drn ])?
        await client.db.delete address
        console.log "deleted db: #{address} for drn: #{drn}."
        delete db.addresses[ drn ]
        updated = true
      for collection in db.collections
        if collection.bynames?[ drn ]?
          delete collection.bynames[ drn ]
          updated = true
    if updated then await updateConfig graphene
