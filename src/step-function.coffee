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
  getStepFunctionARN
} from "@dashkite/dolores/step-function"

buildTarget = (name) ->
  arn = await getLambdaARN name
  parts = arn.split ":"
  parts[0..-2].join ":"

export default ( genie, options ) ->
  if options[ "step-function" ]?
    { lambda, namespace } = options
    { name, path, imports } = options[ "step-function" ]

    genie.define "sky:step-function:publish",
      [
        "sky:lambda:publish:*"
      ], (environment) ->
        dictionary = {}
        resources = lambdas: [], stepFunctions: []

        for handler in ( lambda?.handlers ? [] )
          arn = await buildTarget "#{namespace}-#{environment}-#{handler.name}"
          dictionary[ handler.name ] = arn
          resources.lambdas.push arn
        for value in imports
          if Type.isString value
            arn = await buildTarget value
            dictionary[ value ] = arn
            resources.lambdas.push arn
          else if Type.isObject value
            _name = value.alias ? value.name
            arn = await do ->
              switch value.type
                when "lambda" then buildTarget value.name
                when "step-function" then getStepFunctionARN value.name
                else throw new Error "unknown import type #{value.type}"
            if !arn?
              throw new Error "arn not found for #{JSON.stringify value}"
            dictionary[_name] = arn
            type = if value.type == "lambda" then "lambdas" else "stepFunctions"
            resources[ type ].push arn
          else
            throw new Error "unprocessible import format\n #{JSON.stringify value}"

        createStepFunction {
          name: "#{namespace}-#{environment}-#{name}"
          description: YAML.load await FS.readFile path
          dictionary
          resources
        }


    genie.define "sky:step-function:start", (environment) ->
      startStepFunction "#{namespace}-#{environment}-#{name}"

    genie.define "sky:step-function:halt", (environment) ->
      haltStepFunction "#{namespace}-#{environment}-#{name}"
      
    genie.define "sky:step-function:delete", (environment) ->
      deleteStepFunction "#{namespace}-#{environment}-#{name}"