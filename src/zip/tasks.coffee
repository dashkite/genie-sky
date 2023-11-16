# Please see docs/zip.md for documentation.

import FS from "fs/promises"
import Path from "path"
import JSZip from "jszip"
import { log } from "@dashkite/dolores/logger"
import esbuild from "esbuild"
import * as Time from "@dashkite/joy/time"

normalize = ( path ) ->
  if path[0] == "/" || path[0] == "."
    path
  else
    "./#{ path }"
  
split = ( path ) -> path.split Path.sep

join = ( items ) -> Path.join items...

cache = {}

read = ( path ) ->
  cache[ path ] ?= await do ->
    FS.readFile path, "utf8"

exists = ( path ) ->
  try
    await read path
    true
  catch
    false

extension = ( extension, path ) ->
  Path.join ( Path.dirname path ),
    ( Path.basename path, Path.extname path ) + extension

choose = ( paths ) ->
  for path in paths
    if await exists Path.join path, "package.json"
      return path
  null
    
getPackage = ( root ) ->
  source = Path.join root, "package.json"
  text = await read source
  data = JSON.parse text
  { source, data }

getModule = ( source ) ->

  local = false
  items = split source
  i = items.lastIndexOf "node_modules"
  root = if i > 0
    if items[ i + 1 ][0] == "@"
      join items[0..( i + 2 )]
    else
      join items[0..( i + 1 )]
  else
    local = true
    # TODO this should actually just check all the paths
    # ex: given `../../fubar/foo/build/node/src/index.js`
    # we should check `..`, `../..`, `../../fubar` and so on.
    await choose [
      join items[0..1]
      items[0]
      "."
      join items[0..2]
    ]

  _package = await getPackage root

  if root == "."
    target = Path.relative Paths.build, source
    _package.target = "package.json"
  else
    target = Path.join "node_modules",
      _package.data.name,
      Path.relative root, source
    _package.target = Path.join "node_modules",
      _package.data.name,
      "package.json"

  { source, root, local, target, package: _package }

addFile = ({ zip, source, target }) ->
  zip.file target, await read source

Paths =
  zip:
    directory: Path.resolve ".sky", "build"

bundle = ({ name, path }) ->

  Paths.zip.file = Path.join Paths.zip.directory, "#{ name }.zip"
  Paths.entry = Path.join "build", "node", ( extension ".js", path )
  Paths.build = Path.resolve Path.dirname Paths.entry

  zip = new JSZip

  { metafile } = await esbuild.build
    entryPoints: [ Paths.entry ]
    bundle: true
    sourcemap: false
    platform: "node"
    conditions: [ "node" ]
    outfile: "/dev/null"
    external: [ "@aws-sdk/*" ]
    metafile: true

  files = {}
  for source, _ of metafile.inputs
    m = await getModule source
    files[ m.target ] = { source, m... }
    files[ m.package.source ] ?= m.package

  await Promise.all do ->
    for { source, target } in Object.values files
      addFile { zip, source, target }

  buffer = await zip.generateAsync
    type: "nodebuffer"
    compression: "DEFLATE"
    compressionOptions:
      level: 9

  await FS.mkdir Paths.zip.directory, recursive: true
  await FS.writeFile  Paths.zip.file, buffer
  
Tasks =

  zip: ({ lambda }) ->
    for handler in lambda
      await bundle handler

  clean: ->
    try
      await FS.rm Paths.zip.directory, recursive: true

export default Tasks
