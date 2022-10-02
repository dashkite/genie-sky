import Path from "node:path"
import * as m from "@dashkite/masonry"
import * as Fn from "@dashkite/joy/function"
import * as It from "@dashkite/joy/iterable"
import * as K from "@dashkite/katana/sync"
import { convert } from "@dashkite/bake"

diff = (publish, operations) ->

  # first, get the list of published items
  published = await do Fn.flow [
    operations.list
    # filter out items that are not in scope
    # so we don't remove them...
    It.select ( item ) -> 
      !publish.target? || item.key.startsWith publish.target
    It.reduce ( Fn.tee (( result, item ) -> result[ item.key ] = item ) ), {}
  ]

  # next, iterate thru the filesystem
  await do m.start [
    m.glob ( publish?.glob ? "**/*" ), ( publish?.root ? "." )
    m.readBinary
    m.hash
    It.map ({ source, input, hash }) ->
      key = do ->
        if publish?.target?
          Path.join publish.target, source.path
        else 
          source.path
      content = convert from: "bytes", to: publish.encoding, input
      remote = published[ key ]
      if !remote?
        operations.add key, content
      else if hash != ( remote.hash ? m.computeHash remote.content )
        operations.update key, content
        delete published[ key ]
      else
        delete published[ key ]
  ]

  # anything left in published has no local counterpart,
  # so delete it
  for key, _ of published
    operations.delete key 


export { diff }