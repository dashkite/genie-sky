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
import { getDomain, getDRN, getDescription } from "../helpers"

getTLD = Fn.pipe [
  Text.split "."
  ( components ) -> components[-2..]
  It.join "."
]

getRules = ({ rules, namespace }) ->
  for rule in rules
    rule.domains = 
      for domain in rule.domains
        await getDomain domain
    handler = await getLambda await getDRN Name.getURI { type: "lambda", namespace, name: rule.handler }
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

  genie.define "sky:alb:publish", ->
    domain = await getDomain alb.domain
    uri = Name.getURI { type: "alb", namespace, name: alb.name }
    context =
      name: await getDRN uri
      description: alb.description ? await getDescription uri
      zone: id: await getHostedZoneID getTLD domain
      domain: domain
      subnets: await VPC.Subnets.list alb.vpc ? "default"
      security:
        groups: await VPC.SecurityGroups.list alb.vpc
      certificate: arn: await getCertificateARN getTLD domain
      handler: await getLambda await getDRN Name.getURI { type: "lambda", namespace, name: alb.handler }
      rules: await getRules { rules: alb.rules, namespace }
      headers: if alb.headers? then await getHeaders alb.headers  
    deployStack context.name,
      await templates.render "template.yaml", context

  genie.define "sky:alb:delete", ->
    deleteStack await getDRN Name.getURI { type: "alb", namespace, name: alb.name }

