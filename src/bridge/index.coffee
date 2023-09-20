import { guard } from "./helpers"

import {
  getLambdaARN
} from "@dashkite/dolores/lambda"

import {
  createRule
  deleteRule
} from "@dashkite/dolores/events"


buildTarget = (name) ->
  arn = await getLambdaARN name
  parts = arn.split ":"
  Arn: parts[0..-2].join ":"
  Id: name

export default (genie, { namespace, bridge, lambda }) ->

  genie.define "sky:bridge:publish", 
    [ 
      "sky:roles:publish:*"
      "sky:lambda:publish:*" 
    ], 
    guard (environment) ->
      { name } = lambda.handlers[0] 
      await createRule {
        name: "#{namespace}-#{environment}-#{bridge.name}-bridge"
        target: await buildTarget "#{namespace}-#{environment}-#{name}"
        schedule: bridge.schedule
      }    
    
  genie.define "sky:bridge:delete", guard (environment) ->
    deleteRule "#{namespace}-#{environment}-#{bridge.name}-bridge"