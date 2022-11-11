import FS from "node:fs/promises"
import * as Fn from "@dashkite/joy/function"
import * as Type from "@dashkite/joy/type"
import * as It from "@dashkite/joy/iterable"
import * as Text from "@dashkite/joy/text"
import Templates from "@dashkite/template"
import compress from "brotli/compress"
import { convert } from "@dashkite/bake"

import { guard } from "../helpers"
import { getLatestLambdaARN } from "@dashkite/dolores/lambda"
import { getHostedZoneID } from "@dashkite/dolores/route53"
import { deployStack, deleteStack } from "@dashkite/dolores/stack"

qname = ({ namespace, name, environment }) ->
  "#{namespace}-#{environment}-#{name}"

getDescription = ({ namespace, environment, edge }) ->
  edge.description ? 
    Text.titleCase "#{ namespace } #{ edge.name } (#{ environment })"


getTLD = Fn.pipe [
  Text.split "."
  ( components ) -> components[-2..]
  It.join "."
]

awsCase = Fn.pipe [
  Text.normalize
  Text.titleCase 
  Text.camelCase 
  Text.capitalize
]

getAliases = ( aliases ) ->
  for alias in aliases
    if Type.isString alias
      domain: alias
    else
      alias

getCertificateAliases = ( aliases ) ->
  result = {}
  for alias in aliases
    tld = getTLD alias.domain 
    result[ tld ] ?= "*.#{tld}"
  Object.values result  

getDNSEntries = ( aliases ) ->
  result = {}
  for alias in aliases
    tld = getTLD alias.domain 
    result[ tld ] ?=
      tld: tld
      zone: await getHostedZoneID tld
      aliases: []
    result[ tld ].aliases.push alias.domain
  Object.values result

getHeaders = ( headers ) ->
  for { name, value } in headers
    if value.startsWith "$"
      [ operation, operand ] = Text.split /\s+/, value
      value = switch operation
        when "$secret"
          await getSecretReference operand
        when "$path"
          convert from: "bytes", to: "base64", 
            compress await FS.readFile operand
        else
          throw new Error "Sky Presets: edge: 
            uknown operator [ #{ operator } ]"
    { name, value }

getOrigins = ({ origin, origins }) ->
  origins ?= [ origin ]
  for origin in origins
    if Type.isString origin
      domain: origin
    else if origin.headers?
      { origin..., headers: await getHeaders origin.headers }
    else origin
      
getHandlers = ({ namespace, environment, handlers }) ->
  for { name, event, body } in handlers       
    event: event ? name
    includesBody: body ? false
    arn: await getLatestLambdaARN qname { namespace, environment, name }     

export default (genie, { namespace, lambda, edge }) ->

  templates = Templates.create "#{__dirname}"
  templates._.h.registerHelper { awsCase }

  genie.define "sky:edge:publish", guard (environment) ->
    name = edge.name ? "edge"
    aliases = getAliases edge.aliases
    template = await templates.render "template.yaml",
      name: name
      namespace: namespace
      environment: environment
      description: getDescription { namespace, environment, edge }
      aliases: aliases
      dns: await getDNSEntries aliases
      # TODO possibly vary by environment
      cache:
        ttl:
          min: 0
          max: 31536000
          default: 0
      certificate:
        verification: edge.certificate.verification
        aliases: getCertificateAliases aliases
      origins: await getOrigins edge
      handlers: if lambda?.handlers? then getHandlers lambda.handlers
    deployStack (qname { namespace, name, environment }), template      
      
  genie.define "sky:edge:delete", guard (environment) ->
    deleteStack "#{namespace}-#{name}-#{environment}"