import FS from "fs/promises"

import {
  publishLambda
  versionLambda
  deleteLambda
} from "@dashkite/dolores/lambda"

import { 
  getRoleARN
} from "@dashkite/dolores/roles"

export default (genie, { namespace, lambda, variables }) ->
  
  genie.define "sky:lambda:update",
    [ 
      "clean"
      "sky:role:publish:*"
      "sky:zip:*" 
    ], (environment) ->

      for handler in lambda.handlers

        data = await FS.readFile "build/lambda/#{ handler.name }.zip"

        name = "#{namespace}-#{environment}-#{handler.name}"

        role = await getRoleARN name

        await publishLambda name, data, {
          handler: "build/lambda/#{ handler.name }/index.handler"
          handler.configuration...
          environment: { environment, variables... }
          role
        }
  
  genie.define "sky:lambda:version", (environment, name) ->
    versionLambda "#{namespace}-#{environment}-#{name}"

  genie.define "sky:lambda:delete", (environment, name) ->
    deleteLambda "#{namespace}-#{environment}-#{name}"
