import * as Fn from "@dashkite/joy/function"
import * as Type from "@dashkite/joy/type"
import * as It from "@dashkite/joy/iterable"
import * as Text from "@dashkite/joy/text"
import Templates from "@dashkite/template"
import { guard } from "../helpers"
import { getLatestLambdaARN } from "@dashkite/dolores/lambda"
import { getCertificateARN } from "@dashkite/dolores/acm"
import { getHostedZoneID } from "@dashkite/dolores/route53"
import { deployStack, deleteStack } from "@dashkite/dolores/stack"

tld = (domain) -> It.join ".", ( Text.split ".", domain )[-2..]

templateCase = Fn.pipe [
  Text.normalize
  Text.titleCase 
  Text.camelCase 
  Text.capitalize
]

export default (genie, { namespace, lambda, edge }) ->

  # TODO add lambda versioning
  genie.define "sky:edge:publish", 
    [ 
      "sky:roles:publish:*"
      "sky:lambda:publish:*" 
    ], 
    guard (environment) ->
      origins = if edge.origins? then edge.origins else [ edge.origin ]
      templates = Templates.create "#{__dirname}"
      template = await templates.render "template.yaml",
        name: edge.name ? namespace
        namespace: namespace
        environment: environment
        description: edge.description ?
          "#{Text.titleCase namespace} #{Text.titleCase environment}"
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
          certificate: await getCertificateARN edge.name
        origins: origins
        handlers: await do ->
          for handler in lambda.handlers
            event: handler.event ? handler.name
            includesBody: handler.includesBody ? false
            arn: await getLatestLambdaARN "#{namespace}-#{environment}-#{handler.name}"
      deployStack "#{namespace}-#{environment}", template      
      
  genie.define "sky:edge:delete", guard (environment) ->
    deleteStack "#{namespace}-#{environment}"