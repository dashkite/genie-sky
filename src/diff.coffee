import Path from "node:path"
import * as m from "@dashkite/masonry"
import * as Fn from "@dashkite/joy/function"
import * as It from "@dashkite/joy/iterable"
import * as K from "@dashkite/katana/sync"

import { confidential } from "panda-confidential"

Confidential = confidential()

hash = (content) ->
  ( Confidential.hash Confidential.Message.from "bytes", content ).to "base64"

diff = (publish, operations) ->

  # first, get the list of published items
  published = ( await operations.list() )
    .map (item) -> 
      { 
        item...
        hashed: hash item.content
      }
    .reduce (( result, item ) -> result[ item.key ] = item.hashed ; result ), {}

  # next, iterate thru the filesystem
  await do m.start [
    m.glob ( publish?.glob ? "**/*" ), ( publish?.root ? "." )
    m.read
    It.map Fn.flow [
      K.read "input"
      K.read "source"
      K.push ( source, input ) ->
        content = Uint8Array.from input
        key: do ->
          if publish?.target?
            Path.join publish.target, source.path
          else 
            source.path
        content: content
        # TODO if we use MD5 we can probably avoid hashing
        #      if hooks provide hashed value, ex: from S3
        hashed: hash content
      # compare each item to the published version if any
      K.peek ({ key, content, hashed }) ->
        _hashed = published[ key ]
        if !_hashed?
          await operations.add key, content
        else if _hashed != hashed
          await operations.update key, content
          delete published[ key ]
        else
          delete published[ key ]
    ]
  ]

  # anything left in published has no local counterpart,
  # so delete it
  for key, _ of published
    console.log "... deleting [ #{ key } ]"
    operations.delete { key }


export { diff }