import FS from "fs/promises"
import sort from "sort-package-json"
import { Messages } from "@dashkite/messages"
import { Name } from "@dashkite/name"
import catalog from "./catalog"
import OS from "node:os"
import Crypto from "node:crypto"
import * as Fn from "@dashkite/joy/function"
import * as Text from "@dashkite/joy/text"
import { getHash } from "@dashkite/masonry/atlas"
import { command as exec } from "execa"
import { convert } from "@dashkite/bake"
import YAML from "js-yaml"
import * as Val from "@dashkite/joy/value"

messages = Messages.create()
messages.add catalog

guard = (f) ->
  (args...) ->
    if f.length == args.length
       f args...
    else
      fatal "missing arguments",
        expected: f.length
        got: args.length

getPackage = do (cache = null) -> ->
  cache ?= JSON.parse await FS.readFile "./package.json", "utf8"

log = ( key, context ) ->
  console.log "sky:presets: " + messages.message key, context

warn = ( key, context ) ->
  console.warn "sky:presets: " + messages.message key, context

fatal = ( key, context ) ->
  console.error "sky:presets: " + messages.message key, context

run = ( action, options ) ->
  exec action, 
    { stdout: "inherit", stderr: "inherit", shell: true, options... }

getBranch = -> run "git branch --show-current"

md5 = (buffer) ->
  convert from: "bytes", to: "base36",
    new Uint8Array Crypto.createHash('md5').update(buffer).digest().buffer

getLocalAddress = do ( address = undefined ) ->
  ->
    address ?= await do ->
      { mac } = OS.networkInterfaces().en0[0]
      branch = await getBranch()
      md5 "#{mac} #{branch}"

getDRN = ( uri ) ->
  { namespace, name } = Name.parse uri
  mode = process.env.mode ? "development"
  address = if mode == "development"
    await getLocalAddress()
  else mode
  ( "#{namespace}-#{name}-#{address}" )[...32]

getSubdomain = ( uri ) ->
  { name } = Name.parse uri
  mode = process.env.mode ? "development"
  if mode == "production"
    name
  else 
    address = if mode == "development"
      await getLocalAddress()
    else mode
    "#{name}-#{address}"

getDomain = ( uri ) ->
  { namespace, name, tld, type, region } = Name.parse uri
  region ?= "us-east-1"
  subdomain = await getSubdomain uri
  switch type
    when "s3"
      "#{subdomain}.s3.#{region}.amazonaws.com"
    when "s3-website"
      # TODO handle .region case
      "#{subdomain}.s3-website-#{region}.amazonaws.com"
    else
      "#{subdomain}.#{namespace}.#{tld}"

getDescription = ( uri ) ->
  { namespace, name } = Name.parse uri
  mode = process.env.mode ? "development"
  if mode == "development"
    address = await getLocalAddress()
    Text.titleCase "#{ namespace } #{ name } #{ mode } #{address}"
  else
    Text.titleCase "#{ namespace } #{ name } #{ mode }"

cache = {}

read = (path) ->
  Val.clone cache[path] ?= YAML.load await FS.readFile path, "utf8"

write = (path, updated) ->
  unless Val.equal cache[path], updated
    cache[path] = updated
    FS.writeFile path, YAML.dump updated

yaml = { read, write }

export { 
  guard, getPackage, getHash, log, 
  warn, fatal, getDRN, getSubdomain, yaml, 
  getDomain, getDescription
}