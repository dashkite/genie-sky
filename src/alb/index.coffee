import * as Fn from "@dashkite/joy/function"
import * as It from "@dashkite/joy/iterable"
import * as Text from "@dashkite/joy/text"

import Templates from "@dashkite/template"

import * as VPC from "@dashkite/dolores/vpc"
import { getCertificateARN } from "@dashkite/dolores/acm"
import { getLambda } from "@dashkite/dolores/lambda"
import { getHostedZoneID } from "@dashkite/dolores/route53"
import { getSecretReference } from "@dashkite/dolores/secrets"
import {
  deployStack
  deleteStack
} from "@dashkite/dolores/stack"

import { guard } from "../helpers"

qname = ({ namespace, name, environment }) ->
  "#{namespace}-#{environment}-#{name}"

getDescription = ({ namespace, environment, alb }) ->
  alb.description ? 
    Text.titleCase "#{ namespace } #{ alb.name } (#{ environment })"

getName = ({ namespace, environment, alb }) ->
  qname { namespace, environment, name: alb.name }


getTLD = Fn.pipe [
  Text.split "."
  ( components ) -> components[-2..]
  It.join "."
]

getRules = ({ rules, namespace, environment }) ->
  for rule in rules
    handler = await getLambda qname {
      namespace
      name: rule.handler
      environment
    }
    { rule..., handler }

getHeaders = ( headers ) ->
  for { name, value } in headers
    if value.startsWith "$"
      [ operation, operand ] = Text.split /\s+/, value
      value = switch operation
        when "$secret"
          await getSecretReference operand
        else operand
    { name, value }

awsCase = Fn.pipe [
  Text.normalize
  Text.titleCase 
  Text.camelCase 
  Text.capitalize
]

increment = ( n ) -> n + 1

export default (genie, { namespace, alb, lambda }) ->

  templates = Templates.create "#{__dirname}"
  templates._.h.registerHelper { awsCase, increment }

  genie.define "sky:alb:publish", guard (environment) ->
    context =
      name: getName { namespace, environment, alb }
      description: getDescription { namespace, environment, alb }
      zone: id: await getHostedZoneID getTLD alb.domain
      domain: alb.domain
      subnets: await VPC.Subnets.list alb.vpc ? "default"
      security:
        groups: await VPC.SecurityGroups.list alb.vpc
      certificate: arn: await getCertificateARN getTLD alb.domain
      handler: await getLambda qname {
        namespace
        name: alb.handler
        environment
      }
      rules: await getRules { rules: alb.rules, namespace, environment }
      headers: if alb.headers? then await getHeaders alb.headers  
    deployStack context.name,
      await templates.render "template.yaml", context

  genie.define "sky:alb:delete", guard (environment) ->
    deleteStack getName { namespace, environment, alb }

