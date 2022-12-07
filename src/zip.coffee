import FS from "fs/promises"
import Path from "path"
# import YAML from "js-yaml"
# import { confidential } from "panda-confidential"
import { guard } from "./helpers"
import execa from "execa"
# import * as Fn from "@dashkite/joy/function"
# import * as It from "@dashkite/joy/iterable"
# import * as Obj from "@dashkite/joy/object"
import * as Type from "@dashkite/joy/type"
import { generic } from "@dashkite/joy/generic"
import * as Text from "@dashkite/joy/text"
import * as Atlas from "@dashkite/atlas"
import { FileReference } from "@dashkite/atlas"

# deliver = generic
#   name: "deliver"
#   description: "Generate Import Map URLs"
#   default: ({ name, version }) ->
#     "node_modules/#{ name }"

# generic deliver, Type.isString, ( name ) ->
#   "node_modules/#{ name }"

# generic deliver, ( Type.isKind Atlas.FileReference ), ( reference ) ->
#   { name, hash } = reference
#   if Text.startsWith "@", name
#     name = name[1..]
#   console.log reference
#   "https://modules.dashkite.com/#{name}/#{hash}/"

# generic deliver, ( Type.isKind Atlas.Scope ), ({ reference }) -> deliver reference

# generic deliver, ( Type.isKind Atlas.ParentScope ), ({ reference }) ->
#   # hacky AF but just need to get this working
#   # amounts to a no-op for file references
#   ( deliver reference ).replace "@#{ reference.version }", ""

getDependencies = ( path ) ->
  console.log "sky presets: atlas: starting"

  # TODO possibly support this interface in Atlas directly?
  console.log "sky presets: atlas: reading package.json"
  pkg = JSON.parse await FS.readFile Path.resolve path, "package.json"

  console.log "sky presents: atlas: creating file reference", path
  generator = await Atlas.Reference.create pkg.name, "file:#{path}"
  generator.root = "."

  generator.scopes

exec = ( command ) ->
  execa.command command,
    shell: true, stripFinalNewline: true

bundle = ({ name, path }) ->

  dependencies = await getDependencies "."
  
  await FS.mkdir "build/lambda/#{ name }/node_modules", recursive: true
  
  loop
    try
      await FS.readdir "build/node/src"
      break
  
  await FS.cp "build/node/src", "build/lambda/#{ name }", recursive: true

  for dependency from dependencies
    if Type.isType FileReference, dependency
      await exec "npm pack #{ dependency.url }"
    else
      await exec "cd build/lambda/#{ name } && npm i #{ dependency.name }"
  
  await exec "cd build/lambda/#{ name } && npm i --production ../../../*.tgz"
  await exec "cd build/lambda/#{ name } && zip -qr ../#{ name }.zip ."


  # await FS.mkdir "build/lambda", recursive: true
  # loop
  #   try
  #     await FS.readdir "build/node/src"
  #     break
  # await FS.cp "build/node/src", "build/lambda/src", recursive: true
  # text = await FS.readFile "package.json", "utf8"  
  # await FS.writeFile "build/lambda/package.json",
  #   text.replaceAll "../", "../../../"
  # text = await FS.readFile "package-lock.json", "utf8"  
  # await FS.writeFile "build/lambda/package-lock.json",
  #   text.replaceAll "../", "../../../"
  # console.log "installing..."
  # await exec "cd build/lambda && npm ci --production --install-links"
  # console.log "zipping..."
  # await exec "zip -qr build/lambda.zip build/lambda"
  # # processToString exec "shasum -a 256 -p build/lambda.zip"

export default (genie, { lambda }) ->
  genie.define "sky:zip", "build", ->
    for handler in lambda.handlers
      await bundle handler

