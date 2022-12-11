import FS from "fs/promises"
import Path from "path"
import { guard } from "./helpers"
import JSZip from "jszip"
import _glob from "glob"

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
      matchBase: true
      ( error, matches ) ->
        if error? then reject error else resolve matches

cat = ( a, b ) -> [ a..., b... ]

# TODO log errors and write to file when finished
log = ->

readPackage = ( path ) ->
  JSON.parse await FS.readFile ( Path.join path, "package.json" ), "utf8"

findFiles = ( root ) ->
  do ( files = [] ) ->
    for pattern in [ "**/*.js", "**/*.json" ]
      files = cat files, await glob pattern, root
    files

makeDependency = ( name, paths ) ->
  # try the list of paths to find the dependency
  for path in paths
    try
      root = Path.join path, "node_modules", name
      # we don't do anything with the package, we're
      # just using it to verify that the root is the
      # right one...
      await readPackage root
      files = await findFiles root
      return { name, root, files }
    catch error
      if error.code != "ENOENT"
        console.log error
        log error
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
  Promise.all do ->
    for file in files
      addFile {
        zip
        source: join source, file
        target: join target, file
      }

bundle = ({ name, path }) ->

  Paths =
    package: Path.resolve "package.json"
    zip: Path.resolve ".sky", "build", "#{ name }.zip"
    build: Path.resolve "build", "node", Path.dirname path

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

  await FS.mkdir ( Path.dirname Paths.zip ), recursive: true
  await FS.writeFile  Paths.zip, buffer
  
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

