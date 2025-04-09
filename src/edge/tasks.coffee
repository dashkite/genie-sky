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
import * as CF from "@dashkite/dolores/cloudfront"

mode = process.env.mode? "development"

getRootDomain = ( domain ) ->
  ( domain.split "." )[-2..].join "."

awsCase = Fn.pipe [
  Text.normalize
  Text.titleCase 
  Text.camelCase 
  Text.capitalize
]

getCertificateAliases = ( aliases ) ->
  result = {}
  for alias in aliases
    root = getRootDomain await alias
    result[ root ] ?= "*.#{root}"
  Object.values result  

getDNSEntries = ( aliases ) ->
  result = {}
  for alias in aliases
    tld = getRootDomain alias
    if ( zone = await getHostedZoneID tld )?
      [ ..., id ] = zone.split "/"
      result[ tld ] ?= { tld, zone, id, aliases: []}
      result[ tld ].aliases.push alias
    else
      console.warn "genie-sky: unable to find hosted zone
        for tld [ #{ tld } ] (for alias [ #{ alias } ])"
  Object.values result


getOrigins = ({ origin, origins }) ->
  origins ?= [ origin ]
  for { domain, preset } in origins
    switch preset
      when "s3"
        s3: private: true
        domain: domain
      when "website"
        s3: website: true
        domain: domain
      else
        { domain }

hasOAC = ( origins ) ->
  ( origins.find ({ s3 }) -> s3?.private )?

getCachePolicy = ( preset ) ->
  preset ?= if mode == "production"
    "Managed-CachingOptimized"
  else 
    "Managed-CachingDisabled"
  if ( policy = await CF.getCachePolicy preset )?
    policy.id
  else
    throw new Error "Caching policy [ #{ preset } ] not found"

getRequestPolicy = ( preset ) ->
  preset ?= "Managed-AllViewer"
  if ( policy = await CF.getRequestPolicy preset )?
    policy.id
  else
    throw new Error "Request policy [ #{ preset } ] not found"

getResponsePolicy = ( preset ) ->
  preset ?= "Managed-CORS-with-preflight-and-SecurityHeadersPolicy"
  if ( policy = await CF.getResponsePolicy preset )?
    policy.id
  else
    throw new Error "Response policy [ #{ preset } ] not found"

getHandlers = ({ lambda }) ->
  if lambda?
    for { name, event, body } in lambda
      name: name
      event: event ? name
      includesBody: body ? false
      arn: await getLatestLambdaARN name

getDescription = ({ edge }) ->
  edge.description ? edge.name

templates = Templates.create "#{__dirname}"
templates._.h.registerHelper { awsCase }

Tasks =

  deploy: ({ lambda, edge }) ->
    origins = getOrigins edge
    oac = hasOAC origins
    template = await templates.render "template.yaml",
      name: edge.name
      environment: mode
      description: await getDescription { edge }
      oac: oac
      aliases: edge.aliases
      dns: await getDNSEntries edge.aliases
      # TODO should be per origin
      cache: await getCachePolicy edge.cache
      request: await getRequestPolicy edge.request
      response: await getResponsePolicy edge.response
      certificate:
        verification: edge.certificate.verification
        aliases: await getCertificateAliases edge.aliases
      origins: origins
      handlers: await getHandlers { lambda }
    deployStack edge.name, template      
    
  undeploy: ({ lambda, edge }) ->
    deleteStack edge.name


export default Tasks