import { deployALB } from "@dashkite/sky-alb"

import {
  getLambda
} from "@dashkite/dolores/lambda"

import {
  deleteStack
} from "@dashkite/dolores/stack"

export default (genie, { namespace, alb, mixins }) ->

  # TODO add delete / teardown

  # genie.define "publish", [ "update" ], (environment) ->
  genie.define "publish", [ "role:build:*", "sky:update:*" ], (environment) ->
    
    await deployALB {
      arn: ( await getLambda "#{namespace}-#{environment}-lambda" ).arn
      namespace
      base: "#{namespace}-#{environment}"
      name: "#{namespace}-#{environment}-alb"
      alb...
      mixins
    }

  genie.define "sky:alb:delete", (environment) ->
    deleteStack "#{namespace}-#{environment}-alb"

