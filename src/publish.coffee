import FS from "fs/promises"

import {
  publishLambda
  versionLambda
} from "@dashkite/dolores/lambda"

export default (genie, options) ->

  genie.define "publish", [ "build", "zip" ], (environment) ->

    data = await FS.readFile "build/lambda.zip"

    name = "#{options.name}-#{environment}"
    
    await publishLambda name, data, options.lambda
    
    # TODO add versioning, but we need to garbage collect...
    # await versionLambda "#{prefix}-origin-request"