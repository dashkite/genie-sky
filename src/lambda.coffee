import FS from "fs/promises"

import {
  publishLambda
  # versionLambda
} from "@dashkite/dolores/lambda"

import { 
  getRoleARN
} from "@dashkite/dolores/roles"

export default (genie, { namespace, lambda }) ->

  # TODO add delete / teardown
  
  genie.define "sky:update", [ "build", "zip", "role:build:*&" ], (environment) ->

    data = await FS.readFile "build/lambda.zip"

    name = "#{namespace}-#{environment}-lambda"

    role = await getRoleARN "#{name}-role" 

    await publishLambda name, data, {
      lambda...
      role
    }
    
    # TODO add versioning, but we need to garbage collect...
    # await versionLambda "#{prefix}-origin-request"
