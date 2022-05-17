import { guard } from "./helpers"

import {
  getLambdaUnqualifiedARN
} from "@dashkite/dolores/lambda"

import {
  createRule
  deleteRule
} from "@dashkite/dolores/events"

import {
  nameLambda
} from "./lambda"

nameBridge = ({ namespace, environment, name }) ->
  if !namespace? || !environment? || !name?
    throw new Error "unable to form bridge name with parameters 
      #{namespace} #{environment} #{name}"  
  
  "#{namespace}-#{environment}-#{name}-bridge"


export default (genie, options) ->
  if options.bridge?
    { namespace } = options

    genie.define "sky:bridge:publish", 
      [ 
        "sky:roles:publish:*"
        "sky:lambda:update:*" 
      ], 
      guard (environment) ->
        for event in options.bridge
          bridge = nameBridge { namespace, environment, name: event.name }

          # Assume lambda for now, but we can introduce types in the future.
          name = nameLambda { namespace, environment, name: event.target }
          # TODO: come up with a non-hacky way to generate IDs to name rules.
          target = 
            Arn: await getLambdaUnqualifiedARN name
            Id: bridge.slice 0, 64

          await createRule {
            name: bridge
            target: target
            schedule: event.schedule
          }    
      
    genie.define "sky:bridge:delete", guard (environment) ->
      deleteRule "#{namespace}-#{environment}-#{bridge.name}-bridge"