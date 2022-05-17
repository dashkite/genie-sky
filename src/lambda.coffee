import FS from "fs/promises"
import { guard } from "./helpers"

import {
  publishLambda
  versionLambda
  deleteLambda
  putSources
  deleteSources
} from "@dashkite/dolores/lambda"

import {
  getStream
} from "@dashkite/dolores/kinesis"

import { 
  getRoleARN
} from "@dashkite/dolores/roles"

nameLambda = ({ namespace, environment, name }) ->
  if !namespace? || !environment? || !name?
    throw new Error "unable to form lambda function name with parameters 
      #{namespace} #{environment} #{name}"  
  
  "#{namespace}-#{environment}-#{name}"

updateLambdas = ({ namespace, environment, lambda, variables, version }) ->

  for handler in lambda?.handlers ? []
    
    try
      # if there's no zip file, the file hasn't changed
      data = await FS.readFile "build/lambda/#{ handler.name }.zip"
    
    if data?

      name = nameLambda { namespace, environment, name: handler.name }

      role = await getRoleARN "#{name}-role"

      await publishLambda name, data, {
        handler: "#{ handler.name }.handler"
        handler.configuration...
        environment: { environment, variables... }
        role
      }

      if version
        await versionLambda name

updateSources = ({ namespace, environment, handler }) ->
  name = nameLambda { namespace, environment, name: handler.name }
  sources = []
  for source in handler.sources
    switch source.type
      when "kinesis"
        stream = await getStream source.name
        if !stream?
          throw new Error "stream #{source.name} is not available"
        sources.push
          BatchSize: source.batchSize ? 1
          Enabled: true
          EventSourceArn: stream.arn
          FunctionName: name
          StartingPosition: "TRIM_HORIZON"
      
      else
        throw new Error "unknown stream type"

  await putSources name, sources


export default (genie, options) ->

  if options.lambda?
    { namespace, lambda, variables } = options

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
      versionLambda nameLambda { namespace, environment, name }

    genie.define "sky:lambda:delete", guard (environment, name) ->
      deleteLambda nameLambda { namespace, environment, name }

    genie.define "sky:lambda:sources:put", guard (environment, name) ->
      handler = lambda.handlers.find (h) -> h.name == name

      if !handler?
        throw new Error "configuration is not available for handler [#{name}]"
      if !handler.sources?
        throw new Error "sources are not configured for handler [#{name}]"

      await updateSources { namespace, environment, handler }

    genie.define "sky:lambda:sources:all:put", guard (environment) ->
      for handler in lambda.handlers
        await updateSources { namespace, environment, handler }

    genie.define "sky:lambda:sources:delete", guard (environment, name) ->
      await deleteSources nameLambda { namespace, environment, name }

    genie.define "sky:lambda:sources:all:delete", guard (environment) ->
      names = lambda.handlers.map (h) -> h.name == name

      for name in names
        await deleteSources nameLambda { namespace, environment, name }
     

export { nameLambda }

# createSourceEvents configuration shape
#  
# BatchSize
# BisectBatchOnFunctionError
# DestinationConfig
# Enabled
# EventSourceArn
# FunctionName
# FunctionResponseTypes
# MaximumBatchingWindowInSeconds
# MaximumRecordAgeInSeconds
# MaximumRetryAttempts
# ParallelizationFactor
# Queues
# SelfManagedEventSource
# SourceAccessConfigurations
# StartingPosition
# StartingPositionTimestamp
# Topics
# TumblingWindowInSeconds