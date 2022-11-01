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
import { getCertificateARN } from "@dashkite/dolores/acm"
import { getHostedZoneID } from "@dashkite/dolores/route53"
import { deployStack, deleteStack } from "@dashkite/dolores/stack"

qname = ({ namespace, name, environment }) ->
  "#{namespace}-#{environment}-#{name}"

tld = (domain) -> It.join ".", ( Text.split ".", domain )[-2..]

templateCase = Fn.pipe [
  Text.normalize
  Text.titleCase 
  Text.camelCase 
  Text.capitalize
]

normalizeHeaders = ( headers ) ->
  for { name, path, value } in headers
    if path?
      value ?= convert from: "bytes", to: "base64", 
        compress await FS.readFile path
    { name, value }

normalizeOrigins = ({ origin, origins }) ->
  origins ?= [ origin ]
  for origin in origins
    if Type.isString origin
      domain: origin
    else if origin.headers?
      { origin..., headers: await normalizeHeaders origin.headers }
    else origin
      
export default (genie, { namespace, lambda, edge }) ->

  genie.define "sky:edge:publish", 
    [ 
      "sky:roles:publish:*"
      "sky:lambda:publish:*" 
    ], 
    guard (environment) ->
      origins = await normalizeOrigins edge
      templates = Templates.create "#{__dirname}"
      name = edge.name ? "edge"
      template = await templates.render "template.yaml",
        name: name
        namespace: namespace
        environment: environment
        description: edge.description ?
          "#{Text.titleCase namespace} #{Text.titleCase name}"
        aliases: aliases = do ->
          for alias in edge.aliases
            if Type.isString alias
              domain: alias
              dns: !( Text.startsWith "*", alias )
            else
              alias.dns ?= !( Text.startsWith "*", alias.domain )
              alias
        dns: await do ->
          result = {}
          for alias in aliases when alias.dns
            domain = tld alias.domain
            result[ domain ] ?= await do ->
              name: templateCase domain
              zone: await getHostedZoneID domain
              aliases: []
            result[ domain ].aliases.push alias.domain
          Object.values result
        cache:
          "price-class": 100
          ttl:
            min: 0
            max: 0
            default: 0
          certificate: await getCertificateARN namespace
        origins: origins
        handlers: await do ->
          for handler in lambda.handlers       
            event: handler.event ? handler.name
            includesBody: handler.includesBody ? false
            arn: await getLatestLambdaARN qname {
              namespace
              name: handler.name
              environment
            }     
      deployStack (qname { namespace, name, environment }), template      
      
  genie.define "sky:edge:delete", guard (environment) ->
    deleteStack "#{namespace}-#{name}-#{environment}"