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

import { Name } from "@dashkite/name"
import * as DRN from "@dashkite/drn"

getTLD = Fn.pipe [
  Text.split "."
  ( components ) -> components[-2..]
  It.join "."
]

getRules = ({ rules, namespace }) ->
  for rule in rules
    rule.domains = 
      for domain in rule.domains
        await DRN.resolve domain
    name = await DRN.resolve {
      type: "lambda"
      namespace
      name: rule.handler
    }
    handler = await getLambda name
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

templates = Templates.create "#{__dirname}"
templates._.h.registerHelper { awsCase, increment }

Tasks =

  deploy: ({ namespace, alb, lambda }) ->
    domain = await DRN.resolve alb.domain
    resources =
      alb: { type: "alb", namespace, name: alb.name }
      lambda: { type: "lambda", namespace, name: alb.handler }
    context =
      name: await DRN.resolve resources.alb
      description: alb.description ? 
        await DRN.describe resources.alb
      zone: id: await getHostedZoneID getTLD domain
      domain: domain
      subnets: await VPC.Subnets.list alb.vpc ? "default"
      security:
        groups: await VPC.SecurityGroups.list alb.vpc
      certificate: arn: await getCertificateARN getTLD domain
      handler: await getLambda await DRN.resolve resources.lambda
      rules: await getRules { rules: alb.rules, namespace }
      headers: if alb.headers? then await getHeaders alb.headers  
    deployStack context.name,
      await templates.render "template.yaml", context

  undeploy: ({ namespace, alb }) ->
    deleteStack await DRN.resolve { 
      type: "alb"
      namespace
      name: alb.name 
    }

export default Tasks
