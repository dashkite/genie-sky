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
    root = getRootDomain alias
    result[ root ] ?=
      tld: root
      zone: await getHostedZoneID root
      aliases: []
    result[ root ].aliases.push alias
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

getCache = ( preset ) ->
  preset ?= if mode == "production" then "static" else "disabled"
  switch preset
    when "disabled"
      "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
    when "static"
      "8fe497a6-f90b-4207-8fb9-eb4214a4f31f"
    when "static-s3"
      "1d763f5c-4594-43b1-a269-07b9e23d6e7d"
    when "dynamic"
      "54919481-e976-4e15-b112-eda3b6c7ede9"
    else
      "a53da372-fd09-496e-bd4a-4e04a9028770"

getHandlers = ({ lambda }) ->
  if lambda?
    for { name, event, body } in lambda
      name: name
      event: event ? name
      includesBody: body ? false
      arn: await getLatestLambdaARN name

getDescription = ({ edge }) ->
  edge.description ? 
    "Distribution [ #{ edge.name } ]"


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
      cache: getCache edge.cache
      certificate:
        verification: edge.certificate.verification
        aliases: await getCertificateAliases edge.aliases
      origins: origins
      handlers: await getHandlers { lambda }
    deployStack edge.name, template      
    
  undeploy: ({ lambda, edge }) ->
    deleteStack edge.name


export default Tasks