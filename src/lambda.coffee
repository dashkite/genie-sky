import FS from "fs/promises"

import {
  publishLambda
  versionLambda
  deleteLambda
} from "@dashkite/dolores/lambda"

import { 
  getRoleARN
} from "@dashkite/dolores/roles"

export default (genie, { namespace, lambda }) ->
  
  genie.define "sky:update", [ "clean", "zip:*" ], (environment) ->

    data = await FS.readFile "build/lambda.zip"

    name = "#{namespace}-#{environment}-lambda"

    role = await getRoleARN "#{name}-role" 

    await publishLambda name, data, {
      lambda...
      role
    }
    
  genie.define "sky:lambda:update", [ "clean", "zip:*" ], (environment) ->

    for handler in lambda.handlers

      data = await FS.readFile "build/lambda.zip"

      name = "#{namespace}-#{environment}-#{handler.name}-lambda"

      role = await getRoleARN "#{namespace}-#{environment}-lambda-role"

      await publishLambda name, data, {
        handler.configuration...
        role
      }
  
  genie.define "sky:lambda:version", (environment, name) ->
    versionLambda "#{namespace}-#{environment}-#{name}-lambda"

  genie.define "sky:lambda:delete", (environment) ->
    name = "#{namespace}-#{environment}-lambda"

    deleteLambda name
