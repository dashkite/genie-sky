import Path from "node:path"
import * as m from "@dashkite/masonry"
import * as Fn from "@dashkite/joy/function"
import * as It from "@dashkite/joy/iterable"
import * as K from "@dashkite/katana/sync"
import { putResource } from "@dashkite/dolores/graphene"
import fetch from "node-fetch"

export default ( genie, options ) ->

  { collections } = options

  genie.define "sky:graphene:publish", (name) ->

    { publish } = collections.find ( collection ) -> name == collection.name

    do m.start [
      m.glob ( publish?.glob ? "**/*" ), ( publish?.root ? "." )
      m.read
      It.map Fn.flow [
        K.read "input"
        K.read "source"
        K.push ( source, input ) ->
          console.log "publishing [ #{source.path} ] ..."
          collection: name
          key: do ->
            if publish?.target?
              Path.join publish.target, source.path
            else 
              source.path
          value: input
        K.peek ({collection, key, value}) ->
          putResource collection, key, value
      ]
    ]