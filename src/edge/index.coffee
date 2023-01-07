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

isS3Origin = ( domain ) ->
  ( "s3" in domain.split "." ) &&
    domain.endsWith ".amazonaws.com"
  
isS3Website= ( domain ) ->
  ( domain.endsWith ".amazonaws.com" ) &&
    ( domain
      .split "."
      .some ( text ) -> text.startsWith "s3-website" )
    
s3Decorator = ( handler ) ->
  ( description ) ->
    for origin in await handler description
      origin.s3 = do ->
        if isS3Origin origin.domain
          private: true
        else if isS3Website origin.domain
          website: true
        else null
      origin

getOrigins = s3Decorator ({ origin, origins }) ->
  origins ?= [ origin ]
  for origin in origins
    if Type.isString origin
      domain: origin
    else if origin.headers?
      { origin..., headers: await getHeaders origin.headers }
    else origin

hasOAC = ( origins ) ->
  ( origins.find ({ s3 }) -> s3?.private )?

# TODO possibly vary by environment
getCache = ( preset ) ->

  switch preset

    when "static"
      # static content so cache everything aggressively
      # but allow for authorized content
      ttl:
        default: 86400 # 1 day
        min: 1
        max: 31536000 # 1 year
      headers: [
          "Authorization"
          "Host"
        ]
      compress: true
      queries: "none"

    when "dynamic"
      # basically we handle the edge caching
      # so turn everything off
      ttl:
        default: 0
        min: 0
        max: 0
      compress: false
      queries: "none"

    # allow for backward compatibility
    else
      # let cloudfront do the caching
      ttl: cache.ttl ? 
        default: 0
        min: 0
        max: 31536000 # 1 year
      compress: true
      headers: [
          "Authorization"
          "Host"
        ]
      queries: "all"

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
    origins = await getOrigins edge
    oac = hasOAC origins
    template = await templates.render "template.yaml",
      name: name
      namespace: namespace
      environment: environment
      description: getDescription { namespace, environment, edge }
      oac: oac
      aliases: aliases
      dns: await getDNSEntries aliases
      cache: getCache edge.cache
      certificate:
        verification: edge.certificate.verification
        aliases: getCertificateAliases aliases
      origins: origins
      handlers: if lambda?.handlers? then getHandlers lambda.handlers
    deployStack (qname { namespace, name, environment }), template      
      
  genie.define "sky:edge:delete", guard (environment) ->
    deleteStack "#{namespace}-#{name}-#{environment}"