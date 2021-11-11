import { deployALB } from "@dashkite/sky-alb"

import {
  getLambda
} from "@dashkite/dolores/lambda"

export default (genie, { namespace, alb }) ->

  # TODO add delete / teardown

  # genie.define "publish", [ "update" ], (environment) ->
  genie.define "publish", (environment) ->
    
    await genie.run "update:#{environment}"

    await deployALB {
      arn: ( await getLambda "#{namespace}-#{environment}-lambda" ).arn
      name: "#{namespace}-#{environment}-alb"
      alb... 
    }
