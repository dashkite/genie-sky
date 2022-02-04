import FS from "fs/promises"
import YAML from "js-yaml"

import * as Type from "@dashkite/joy/type"

import {
  getLambdaARN
} from "@dashkite/dolores/lambda"

import {
  createStepFunction
  deleteStepFunction
  startStepFunction
  haltStepFunction
} from "@dashkite/dolores/step-function"

buildTarget = (name) ->
  arn = await getLambdaARN name
  parts = arn.split ":"
  parts[0..-2].join ":"

export default ( genie, options ) ->
  { lambda, namespace } = options
  { name, path, imports } = options[ "step-function" ]

  genie.define "sky:step-function:publish",
    [
      "sky:lambda:update:*"
    ], (environment) ->
      dictionary = await do ->
        result = {}
        for handler in lambda.handlers
          result[ handler.name ] = await buildTarget "#{namespace}-#{environment}-#{handler.name}"
        for _name in imports
          result[ _name ] = await buildTarget _name
        result

      createStepFunction "#{namespace}-#{environment}-#{name}",
        dictionary,
        YAML.load await FS.readFile path


  genie.define "sky:step-function:start", (environment) ->
    startStepFunction "#{namespace}-#{environment}-#{name}"

  genie.define "sky:step-function:halt", (environment) ->
    haltStepFunction "#{namespace}-#{environment}-#{name}"
    
  genie.define "sky:step-function:delete", (environment) ->
    deleteStepFunction "#{namespace}-#{environment}-#{name}"