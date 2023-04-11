import { inspect } from "node:util"
import * as Graphene from "@dashkite/graphene-core"
import * as Polaris from "@dashkite/polaris"
import { guard, log, warn, fatal, yaml, getDRN, getDomain } from "./helpers"
import { diff } from "./diff"

export default ( genie, { graphene } ) ->
  
  client = Graphene.Client.create()
  
  updateConfig = ( config ) ->
    cfg = await yaml.read "genie.yaml"
    cfg.sky.graphene = config
    yaml.write "genie.yaml", cfg

  genie.define "sky:graphene:deploy", ->
    created = []
    updated = false
    for db in graphene
      drn = await getDRN db.uri
      db.addresses ?= {}
      if !( address = db.addresses[ drn ])?
        { address } = await client.db.create db
        console.log "created db: #{address} for drn: #{drn}."
        db.addresses[ drn ] = address
        updated = true
      for collection in db.collections
        collection.byname ?= await getDomain collection.uri
        if !( _collection = await (client.db address).collection.get collection.byname )?
          _collection = await (client.db address).collection.create { byname: collection.byname }
          console.log "created collection: #{collection.byname} for database: #{address}"
          created.push { address, byname: collection.byname }
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
    for db in graphene
      for collection in db.collections when collection.publish?
        drn = await getDRN db.uri
        { publish, byname } = collection
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
    updated = false
    for db in graphene
      drn = await getDRN db.uri
      if ( address = db.addresses[ drn ])?
        await client.db.delete address
        console.log "deleted db: #{address} for drn: #{drn}."
        delete db.addresses[ drn ]
        updated = true
      for collection in db.collections
        if collection.uri?
          delete collection.byname
          updated = true
    if updated then await updateConfig graphene
