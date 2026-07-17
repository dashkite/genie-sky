# Please see docs/zip.md for documentation.

import FS from "fs/promises"
import Path from "path"
import { bundle as zipBundle } from "@dashkite/masonry-lambda"

Paths =
  zip:
    directory: ( Path.resolve ".sky", "build" )

extension = ( ext, path ) ->
  ( Path.join ( Path.dirname path ),
    ( Path.basename path, ( Path.extname path ) ) + ext )

bundle = ({ name, path }) ->
  Paths.zip.file = ( Path.join Paths.zip.directory, "#{ name }.zip" )
  entry = ( Path.join "build", "node", ( extension ".js", path ) )
  
  buffer = await ( zipBundle entry )
  
  await ( FS.mkdir Paths.zip.directory, { recursive: true } )
  await ( FS.writeFile Paths.zip.file, buffer )

Tasks =

  zip: ({ lambda }) ->
    for handler in lambda
      await ( bundle handler )

  clean: ->
    try
      await ( FS.rm Paths.zip.directory, { recursive: true } )

export default Tasks
