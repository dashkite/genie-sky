import FS from "node:fs/promises"
import * as Fn from "@dashkite/joy/function"
import * as Type from "@dashkite/joy/type"
import * as It from "@dashkite/joy/iterable"
import * as Text from "@dashkite/joy/text"
import Templates from "@dashkite/template"
import compress from "brotli/compress"
import { convert } from "@dashkite/bake"

import { Name } from "@dashkite/name"
import { getDRN, getDescription, getDomain, getRootDomain } from "@dashkite/drn"
import { getLatestLambdaARN } from "@dashkite/dolores/lambda"
import { getHostedZoneID } from "@dashkite/dolores/route53"
import { deployStack, deleteStack } from "@dashkite/dolores/stack"

awsCase = Fn.pipe [
  Text.normalize
  Text.titleCase 
  Text.camelCase 
  Text.capitalize
]

getAliases = ( aliases ) ->
  for uri in aliases
    domain: await getDomain uri
    uri: uri

getCertificateAliases = ( aliases ) ->
  result = {}
  for alias in aliases
    root = getRootDomain alias.uri 
    result[ root ] ?= "*.#{root}"
  Object.values result  

getDNSEntries = ( aliases ) ->
  result = {}
  for alias in aliases
    root = getRootDomain alias.uri 
    result[ root ] ?=
      tld: root
      zone: await getHostedZoneID root
      aliases: []
    result[ root ].aliases.push alias.domain
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
            unknown operator [ #{ operator } ]"
    { name, value }

getOrigins = ({ origin, origins }) ->
  origins ?= [ origin ]
  for origin in origins
    domain = await getDomain origin.domain
    result = 
      switch origin.type
        when "s3"
          s3: private: true
          domain: domain
        when "s3-website"
          s3: website: true
          domain: domain
        else
          { domain }
    if origin.headers?
      result.headers = await getHeaders origin.headers
    result

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

    when "static-s3"
      # static content so cache everything aggressively
      # but allow for authorized content
      ttl:
        default: 86400 # 1 day
        min: 1
        max: 31536000 # 1 year
      headers: [
          "Authorization"
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

getHandlers = ({ namespace, handlers }) ->
  for { name, event, body } in handlers       
    event: event ? name
    includesBody: body ? false
    arn: await getLatestLambdaARN await getDRN { namespace, name }     

export default (genie, { namespace, lambda, edge }) ->

  templates = Templates.create "#{__dirname}"
  templates._.h.registerHelper { awsCase }

  genie.define "sky:edge:publish", ->
    mode = process.env.mode ? "development"
    name = edge.name ? "edge"
    uri = Name.getURI { type: "edge", namespace, name }
    drn = await getDRN uri
    aliases = await getAliases edge.aliases
    origins = await getOrigins edge
    oac = hasOAC origins
    edge.cache ?= if mode == "production" then "static" else "dynamic"
    template = await templates.render "template.yaml",
      name: drn
      namespace: namespace
      environment: mode
      description: await getDescription uri
      oac: oac
      aliases: aliases
      dns: await getDNSEntries aliases
      cache: getCache edge.cache
      certificate:
        verification: edge.certificate.verification
        aliases: getCertificateAliases aliases
      origins: origins
      handlers: if lambda?.handlers? then getHandlers lambda.handlers
    deployStack (await getDRN uri), template      
      
  genie.define "sky:edge:delete", ->
    name = edge.name ? "edge"
    deleteStack await getDRN Name.getURI { type: "edge", namespace, name }