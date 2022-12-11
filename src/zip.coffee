import FS from "fs/promises"
import Path from "path"
# import YAML from "js-yaml"
# import { confidential } from "panda-confidential"
import { guard } from "./helpers"
# import execa from "execa"
# import * as Fn from "@dashkite/joy/function"
# import * as It from "@dashkite/joy/iterable"
# import * as Obj from "@dashkite/joy/object"
# import * as Type from "@dashkite/joy/type"
# import { generic } from "@dashkite/joy/generic"
# import * as Text from "@dashkite/joy/text"
# import * as Atlas from "@dashkite/atlas"
# import { FileReference } from "@dashkite/atlas"
# import semver from "semver"
# import Fetch from "make-fetch-happen"
import JSZip from "jszip"
import _glob from "glob"

glob = ( pattern, path, expand = true ) ->
  new Promise ( resolve, reject ) ->
    _glob pattern, 
      cwd: path
      nodir: true
      ignore: [ "node_modules/**/*", "package-lock.json" ]
      matchBase: true
      ( error, matches ) ->
        if error? then reject error else resolve matches

cat = ( a, b ) -> [ a..., b... ]

# TODO log errors and write to file when finished
log = ->

readPackage = ( path ) ->
  JSON.parse await FS.readFile ( Path.join path, "package.json" ), "utf8"

getPackageFiles = ( root, pkg ) ->
  # we don't actually need pkg b/c we're working from node_modules
  # so npm has already figured out what files are necessary
  do ( files = [] ) ->
    for pattern in [ "**/*.js", "**/*.json" ]
      files = cat files, await glob pattern, root
    files

getPackageMetadata = do ( cache = {}) ->
  ( name, path ) ->
    path = Path.join path, "package-lock.json"
    try
      cache[ path ] ?= JSON.parse await FS.readFile path, "utf8"
    if ( metadata = cache[ path ]?.dependencies?[ name ] )?
      { integrity, version } = metadata
      hash: integrity
      version: version
    else
      console.log "no metadata for", name
      {}

getDependency = ( name, paths ) ->
  for path in paths
    try
      root = Path.join path, "node_modules", name
      pkg = await readPackage root
      files = await getPackageFiles root, pkg
      { hash, version } = await getPackageMetadata name, path
      return { name, root, files, hash, version }
    catch error
      if error.code != "ENOENT"
        console.log error
        log error
  throw new Error "could not resolve #{ name }"

dependencies = {}

addDependencies = ( path, paths = []) ->
  paths.push Path.resolve path
  pkg = await readPackage path
  for name, specifier of pkg.dependencies
    unless ( name.startsWith "@aws-" ) || dependencies[ name ]?
      dependency = await getDependency name, paths
      dependencies[ name ] = dependency
      await addDependencies dependency.root, paths

Paths =
  hashes: Path.resolve ".sky", "cache", "hashes"
  package: Path.resolve "package.json"

tracked = {}

track = ( zip ) ->
  zip.forEach ( path, description ) ->
    unless description.dir
      tracked[ path ] = { keep: false, path }
      
keep = ({ path, source, refresh }) ->
  tracked[ path ] = { keep: true, path, source, refresh }

refreshFiles = ({ mname, root, files }) ->
  for file in files
    keep
      source: Path.join root, file
      path: Path.join "node_modules", mname, file
      refresh: true

keepFiles = ({ mname, root, files }) ->
  for file in files
    keep
      source: Path.join root, file
      path: Path.join "node_modules", mname, file
      refresh: false


content = ({ description, zip }) ->
  if description.refresh
    FS.readFile description.source, "utf8"
  else
    try
      zip
        .file description.path
        .async "nodebuffer"
    catch
      FS.readFile description.source, "utf8"

rebuild = ( zip ) ->
  do ({ fresh, path, description } = {}) ->
    fresh = new JSZip
    for path, description of tracked when description.keep
      fresh.file path, await content { description, zip }
    fresh

bundle = ({ name, path }) ->

  Object.assign Paths,
    zip: Path.resolve ".sky", "build", "#{ name }.zip"
    build: Path.resolve "build", "node", Path.dirname path

  zip = new JSZip
  hashes = {}

  try
    data = await FS.readFile Paths.zip
    await zip.loadAsync data
    hashes = JSON.parse await FS.readFile Paths.hashes, "utf8"

  # set up diff for later
  track zip

  await addDependencies "."

  for mname, { root, files, local, hash } of dependencies
    if !( hash? ) || hashes[ mname ] != hash
      hashes[ mname ] = hash if hash?
      refreshFiles { mname, root, files }
    else
      keepFiles { mname, root, files }

  for file in await glob "**/*.js", Paths.build
    keep
      source: Path.join Paths.build, file
      path: file

  keep
    source: Paths.package
    path: "package.json"

  zip = await rebuild zip
  
  buffer = await zip.generateAsync
    type: "nodebuffer"
    compression: "DEFLATE"
    compressionOptions:
      level: 9

  await FS.mkdir ( Path.dirname Paths.zip ), recursive: true
  await FS.mkdir ( Path.dirname Paths.hashes ), recursive: true
  await FS.writeFile  Paths.zip, buffer
  await FS.writeFile Paths.hashes, JSON.stringify hashes
  
export default (genie, { lambda }) ->

  genie.define "sky:zip", "build", ->
    for handler in lambda.handlers
      await bundle handler

  genie.define "sky:zip:build:clean", ->
    try
      FS.rm ".sky/build", recursive: true

  genie.define "sky:zip:cache:clean", ->
    try
      FS.rm ".sky/cache", recursive: true

  genie.define "sky:zip:clean", [
    "sky:zip:build:clean"
    "sky:zip:cache:clean"
  ]

