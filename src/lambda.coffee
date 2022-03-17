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
  
  genie.define "sky:lambda:publish",
    [ 
      "clean"
      "sky:role:publish:*"
      "sky:zip:*" 
    ], (environment) ->
      if !environment?
        throw new Error "sky:lambda:publish environment is undefined"

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
  
  genie.define "sky:lambda:version", (environment, name) ->
    if !environment? || !name?
      throw new Error "sky:lambda:version environment and name must be defined"

    versionLambda "#{namespace}-#{environment}-#{name}"

  genie.define "sky:lambda:delete", (environment, name) ->
    if !environment? || !name?
      throw new Error "sky:lambda:delete environment and name must be defined"

    deleteLambda "#{namespace}-#{environment}-#{name}"
