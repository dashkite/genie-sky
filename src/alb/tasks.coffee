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

import * as DRN from "@dashkite/drn-sky"

getTLD = Fn.pipe [
  Text.split "."
  ( components ) -> components[-2..]
  It.join "."
]

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

  deploy: ({ alb }) ->
    context =
      name: alb.name
      description: alb.description ? "ALB #{ alb.name }"
      zone: id: await getHostedZoneID getTLD alb.domain
      domain: alb.domain
      subnets: await VPC.Subnets.list alb.vpc ? "default"
      security:
        groups: await VPC.SecurityGroups.list alb.vpc
      certificate: arn: await getCertificateARN getTLD alb.domain
      handler: await getLambda alb.lambda
      rules: alb.rules
      headers: if alb.headers? then await getHeaders alb.headers  
    deployStack context.name,
      await templates.render "template.yaml", context

  undeploy: ({ alb }) ->
    deleteStack: alb.name 

export default Tasks
