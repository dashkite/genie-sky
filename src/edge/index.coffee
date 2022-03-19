import * as It from "@dashkite/joy/iterable"
import * as Text from "@dashkite/joy/text"
import Templates from "@dashkite/template"
import { guard } from "../helpers"
import { getLatestLambdaARN } from "@dashkite/dolores/lambda"
import { getCertificateARN } from "@dashkite/dolores/acm"
import { getHostedZoneID } from "@dashkite/dolores/route53"
import { deployStack, deleteStack } from "@dashkite/dolores/stack"

tld = (domain) -> It.join ".", ( Text.split ".", domain )[-2..]

export default (genie, { namespace, lambda, edge }) ->

  # TODO add lambda versioning
  genie.define "sky:edge:publish", 
    [ 
      "sky:roles:publish:*"
      "sky:lambda:publish:*" 
    ], 
    guard (environment) ->
      domain = tld edge.aliases[0].domain
      templates = Templates.create "#{__dirname}"
      template = await templates.render "template.yaml",
        name: edge.name ? namespace
        namespace: namespace
        environment: environment
        description: edge.description ?
          "#{Text.titleCase namespace} #{Text.titleCase environment}"
        "hosted-zone": await getHostedZoneID domain
        aliases: edge.aliases
        cache:
          "price-class": 100
          ttl:
            min: 0
            max: 0
            default: 0
          certificate: await getCertificateARN domain
        domain: domain
        origin: edge.origin
        handlers: await do ->
          for handler in lambda.handlers
            event: handler.event ? handler.name
            arn: await getLatestLambdaARN "#{namespace}-#{environment}-#{handler.name}"
      console.log {template}
      deployStack "#{namespace}-#{environment}", template      
      
  genie.define "sky:edge:delete", guard (environment) ->
    deleteStack "#{namespace}-#{environment}"