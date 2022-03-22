import FS from "fs/promises"
import { guard } from "./helpers"

import {
  publishLambda
  versionLambda
  deleteLambda
} from "@dashkite/dolores/lambda"

import { 
  getRoleARN
} from "@dashkite/dolores/roles"

updateLambdas = ({ namespace, environment, lambda, variables, version }) ->

  for handler in lambda?.handlers ? []
    
    try
      # if there's no zip file, the file hasn't changed
      data = await FS.readFile "build/lambda/#{ handler.name }.zip"
    
    if data?

      name = "#{namespace}-#{environment}-#{handler.name}"

      role = await getRoleARN "#{name}-role"

      await publishLambda name, data, {
        handler: "#{ handler.name }.handler"
        handler.configuration...
        environment: { environment, variables... }
        role
      }

      if version
        await versionLambda name

export default (genie, { namespace, lambda, variables }) ->
  
  genie.define "sky:lambda:update",
    [ 
      "clean"
      "sky:roles:publish:*"
      "sky:zip:*" 
    ],
    guard (environment) ->
      updateLambdas {
        namespace
        environment
        lambda
        variables
        version: false 
      }

  genie.define "sky:lambda:publish",
    [ 
      "clean"
      "sky:roles:publish:*"
      "sky:zip:*" 
    ],
    guard (environment) ->
      updateLambdas {
        namespace
        environment
        lambda
        variables
        version: true
      }

  genie.define "sky:lambda:version", guard (environment, name) ->
    versionLambda "#{namespace}-#{environment}-#{name}"

  genie.define "sky:lambda:delete", guard (environment, name) ->
    deleteLambda "#{namespace}-#{environment}-#{name}"
