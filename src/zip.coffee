# Please see docs/zip.md for documentation.

import FS from "fs/promises"
import Path from "path"
import { guard } from "./helpers"
import JSZip from "jszip"
import _glob from "glob"
import { log } from "@dashkite/dolores/logger"

Paths =
  package: Path.resolve "package.json"
  zip:
    directory: Path.resolve ".sky", "build"

glob = ( pattern, path ) ->
  new Promise ( resolve, reject ) ->
    _glob pattern, 
      cwd: path
      nodir: true
      ignore: [
        "node_modules/**/*"
        "package-lock.json"
        "test/**/*"
      ]
      ( error, matches ) ->
        if error? then reject error else resolve matches

cat = ( a, b ) -> [ a..., b... ]

readPackage = ( path ) ->
  JSON.parse await FS.readFile ( Path.join path, "package.json" ), "utf8"

findFiles = ( root ) ->
  do ( files = [] ) ->
    for pattern in [ "**/*.js", "**/*.json" ]
      files = cat files, await glob pattern, root
    files

makeDependency = ( name, paths ) ->
  for path in paths
    try
      root = Path.join path, "node_modules", name
      await readPackage root
      files = await findFiles root
      return { name, root, files }
    catch error
      if error.code != "ENOENT"
        log "zip", "errors", error.message
  throw new Error "could not resolve #{ name }"

crawl = ( path, dependencies = {}, paths = []) ->
  paths.push Path.resolve path
  pkg = await readPackage path
  for name, specifier of pkg.dependencies
    unless ( name.startsWith "@aws-sdk/" ) || dependencies[ name ]?
      dependency = await makeDependency name, paths
      dependencies[ name ] = dependency
      await crawl dependency.root, dependencies, paths
  dependencies

addFile = ({ zip, source, target }) ->
  zip.file target, await FS.readFile source, "utf8"

join = ( root, path ) ->
  if root?
    Path.join root, path
  else
    path

addFiles = ({ zip, source, target, files }) ->
  for file in files
    await addFile {
      zip
      source: join source, file
      target: join target, file
    }

bundle = ({ name, path }) ->

  Paths.zip.file = Path.join Paths.zip.directory, "#{ name }.zip"
  Paths.build = Path.resolve "build", "node", Path.dirname path

  zip = new JSZip

  dependencies = await crawl "."

  for target, dependency of dependencies
    { root, files } = dependency
    await addFiles { zip, source: root, target, files }

  await addFiles {
    zip
    source: Paths.build
    files: await glob "**/*.js", Paths.build
  }

  await addFile {
    zip
    source: Paths.package
    target: "package.json"
  }
  
  buffer = await zip.generateAsync
    type: "nodebuffer"
    compression: "DEFLATE"
    compressionOptions:
      level: 9

  await FS.mkdir Paths.zip.directory, recursive: true
  await FS.writeFile  Paths.zip.file, buffer
  
export default (genie, { lambda }) ->

  genie.define "sky:zip", "build", ->
    for handler in lambda.handlers
      await bundle handler

  genie.define "sky:zip:clean", ->
    try
      FS.rm Paths.zip.directory, recursive: true

