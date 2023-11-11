import FS from "node:fs/promises"
import * as Fn from "@dashkite/joy/function"
import * as Type from "@dashkite/joy/type"
import * as It from "@dashkite/joy/iterable"
import * as Text from "@dashkite/joy/text"
import Templates from "@dashkite/template"
import compress from "brotli/compress"
import { convert } from "@dashkite/bake"

import * as DRN from "@dashkite/drn-sky"
import { getLatestLambdaARN } from "@dashkite/dolores/lambda"
import { getHostedZoneID } from "@dashkite/dolores/route53"
import { deployStack, deleteStack } from "@dashkite/dolores/stack"

getRootDomain = ( domain ) ->
  ( domain.split "." )[-2..].join "."

awsCase = Fn.pipe [
  Text.normalize
  Text.titleCase 
  Text.camelCase 
  Text.capitalize
]

getAliases = ( aliases ) ->
  for uri in aliases
    domain: await DRN.resolve uri
    uri: uri

getCertificateAliases = ( aliases ) ->
  result = {}
  for alias in aliases
    root = getRootDomain await DRN.resolve alias.uri 
    result[ root ] ?= "*.#{root}"
  Object.values result  

getDNSEntries = ( aliases ) ->
  result = {}
  for alias in aliases
    root = getRootDomain await DRN.resolve alias.uri 
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
            uknown operator [ #{ operator } ]"
    { name, value }

getOrigins = ({ origin, origins }) ->
  origins ?= [ origin ]
  for origin in origins
    domain = await DRN.resolve origin.domain
    { type, scope } = DRN.decode origin.domain
    result = 
      switch type
        when "s3"
          switch scope
            when "global", "regional"
              s3: private: true
              domain: domain
            when "website"
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

    when "disabled"
      "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"

    when "static"
      # static content so cache everything aggressively
      # but allow for authorized content
      "8fe497a6-f90b-4207-8fb9-eb4214a4f31f"
      # ttl:
      #   default: 86400 # 1 day
      #   min: 1
      #   max: 31536000 # 1 year
      # headers: [
      #     "Authorization"
      #     "Host"
      #   ]
      # compress: true
      # queries: "none"

    when "static-s3"
      "1d763f5c-4594-43b1-a269-07b9e23d6e7d"

    when "dynamic"
      # basically we handle the edge caching
      # so turn everything off
      # AWS policy: Managed-CachingDisabled
      "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
      # ttl:
      #   default: 0
      #   min: 0
      #   max: 0
      # compress: false
      # queries: "none"

    # allow for backward compatibility
    else
      # let cloudfront do the caching
      "a53da372-fd09-496e-bd4a-4e04a9028770"
      # ttl: cache.ttl ? 
      #   default: 0
      #   min: 0
      #   max: 31536000 # 1 year
      # compress: true
      # headers: [
      #     "Authorization"
      #     "Host"
      #   ]
      # queries: "all"

getHandlers = ({ namespace, lambda }) ->
  if lambda?.handlers?
    for { name, event, body } in lambda.handlers 
      qname = await DRN.resolve { type: "lambda", namespace, name }     
      event: event ? name
      includesBody: body ? false
      arn: await getLatestLambdaARN qname

templates = Templates.create "#{__dirname}"
templates._.h.registerHelper { awsCase }

Tasks =

  deploy: ({ namespace, lambda, edge }) ->
    mode = process.env.mode ? "development"
    name = edge.name ? "edge"
    uri = DRN.encode { type: "edge", namespace, name }
    drn = await DRN.resolve uri
    aliases = await getAliases edge.aliases
    origins = await getOrigins edge
    oac = hasOAC origins
    # TODO should be per origin
    edge.cache ?= do ->
      if mode == "production" then "static" else "dynamic"
    template = await templates.render "template.yaml",
      name: drn
      namespace: namespace
      environment: mode
      description: await DRN.describe uri
      oac: oac
      aliases: aliases
      dns: await getDNSEntries aliases
      cache: getCache edge.cache
      certificate:
        verification: edge.certificate.verification
        aliases: await getCertificateAliases aliases
      origins: origins
      handlers: await getHandlers { namespace, lambda }
    deployStack (await DRN.resolve uri), template      
    
  undeploy: ({ namespace, lambda, edge }) ->
    stack = { type: "edge", namespace, name: edge.name ? "edge" }
    deleteStack await DRN.resolve stack


export default Tasks