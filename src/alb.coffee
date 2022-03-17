import { deployALB } from "@dashkite/sky-alb"

import {
  getLambda
} from "@dashkite/dolores/lambda"

import {
  deleteStack
} from "@dashkite/dolores/stack"

export default (genie, { namespace, alb, lambda, mixins }) ->

  # TODO add delete / teardown

  # genie.define "publish", [ "update" ], (environment) ->
  genie.define "sky:alb:publish", [ "sky:lambda:update:*" ], (environment) ->
    if !environment?
      throw new Error "sky:alb:publish environment is undefined"
    
    { name } = lambda.handlers[0]
    await deployALB {
      arn: ( await getLambda "#{namespace}-#{environment}-#{name}" ).arn
      namespace
      base: "#{namespace}-#{environment}"
      name: "#{namespace}-#{environment}-alb"
      alb...
      mixins
    }

  genie.define "sky:alb:delete", (environment) ->
    if !environment?
      throw new Error "sky:alb:delete environment is undefined"

    deleteStack "#{namespace}-#{environment}-alb"

