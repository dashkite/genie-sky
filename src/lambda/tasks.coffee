import FS from "node:fs/promises"
import Path from "node:path"
import * as Fn from "@dashkite/joy/function"
import { generic } from "@dashkite/joy/generic"
import * as Type from "@dashkite/joy/type"
import * as Text from "@dashkite/joy/text"
import * as Pred from "@dashkite/joy/predicate"
import * as Value from "@dashkite/joy/value"
import * as Time from "@dashkite/joy/time"

import YAML from "js-yaml"

import * as DRN from "@dashkite/drn-sky"

import {
  publishLambda
  versionLambda
  deleteLambda
  createFunctionURL
  updateFunctionURL
  hasFunctionURL
} from "@dashkite/dolores/lambda"

import { 
  getRoleARN
} from "@dashkite/dolores/roles"

import {
  tail
} from "@dashkite/dolores/cloudwatch"

import { Runner } from "#helpers/runner"

run = Runner.make -> import( "./tasks" )

mode = process.env.mode ? "development"

basename = ( path ) ->
  Path.basename path, Path.extname path

Lambda =

  publish: publishLambda
  version: versionLambda
  delete: deleteLambda

  FunctionURL:
    create: createFunctionURL
    update: updateFunctionURL
    has: hasFunctionURL

  isEdge: ( lambda ) ->
    lambda.event in [
      "origin-request"
      "origin-response"
      "viewer-request"
      "viewer-response"
    ]

  configure: ( lambda ) ->

    configuration = { 
      lambda.configuration...
      lambda.configurations?.default...
      ( lambda.configurations?[ mode ] )...
    }

    if Lambda.isEdge lambda
      if configuration.environment?
        console.warn "Environment variables not permitted
          for Edge Lambdas"
      configuration.environment = undefined
    else
      configuration.environment = { 
        NODE_OPTIONS: "--enable-source-maps"
        # placeholder for backward compat
        # remove please future dashkitians
        context: "{}"
        configuration.environment... 
      }

    if lambda.url?.open == true
      # TODO handle case where there's already a policy
      configuration.permissions = [
        StatementId: "public-access"
        FunctionName: lambda.name
        Principal: "*"
        Action: "lambda:InvokeFunctionUrl"
        FunctionUrlAuthType: "NONE"
      ]

    configuration

  deploy: ( lambda ) ->

    try
      data = await FS.readFile ".sky/build/#{ lambda.name }.zip"
    
    if data?
      role = await getRoleARN lambda.name

      configuration = Lambda.configure lambda

      # TODO get lambda from configuration
      await Lambda.publish lambda.name, data, {
        handler: "#{ basename lambda.path }.handler"
        configuration...
        role
      }

      if lambda.version == true
        await Lambda.version lambda.name

      if lambda.url?
        url = if lambda.url == true then {} else lambda.url
        if await Lambda.FunctionURL.has lambda.name
          await Lambda.FunctionURL.update { name: lambda.name, url... }
        else 
          await Lambda.FunctionURL.create { name: lambda.name, url... }


Handlers =

  isPath: Pred.all [
    Text.endsWith ".coffee"
    Pred.negate Value.eq  "index.coffee"
  ]

  # TODO use dynamic imports for this
  generateIndex: ({ generate }) ->
    imports = ""
    handlers = "handlers =\n"

    root = Path.resolve generate.path
    paths = await FS.readdir root

    for path in paths when Handler.isPath path
      fname = Path.basename path, ".coffee"
      rname = Text.uncase fname
      symbol = Text.camelCase rname
      imports += "import #{ symbol } from './#{ fname }'\n"
      handlers += "  '#{ rname }': #{ symbol }\n"

    index = Path.resolve root, "index.coffee"
    await FS.writeFile index, """
      #
      # WARNING This file is automatically generated.
      #
      # DO NOT EDIT.
      #

      #{ imports }
      #{ handlers }
      export default handlers
      """

    # give it a second, in case subsequent tasks
    # need the file we just generated
    Time.sleep 1000

  verify: ({ generate, verify }) ->

    handlers = ( require Path.resolve generate?.path ? verify?.path ).default
    # TODO make this configurable?
    api = YAML.load await FS.readFile "./src/api.yaml", "utf8"
    errors = []

    for rname, resource of api.resources
      if !( _handlers = handlers[ rname ] )?
        errors.push "Missing handlers for resource [ #{ rname } ]"
      else
        for mname, method of resource.methods
          if !( handler = _handlers[ mname ] )?
            errors.push "Missing handler for resource [ #{ rname } ],
              method [ #{ mname } ]"
    
    for rname, _handlers of handlers
      if !( api.resources[ rname ]? )
        errors.push "No resource [ #{ rname } ] for handler"
      else
        for mname, handler of _handlers
          if !( api.resources[ rname ]?.methods[ mname ]? )
            errors.push "No method [ #{ mname } ] in resource
              [ #{ rname } ] for handler"

    if errors.length > 0
      for error in errors
        console.error error
      throw new Error "API handlers mismatch"


LogEvent =

  System:

    Dictionary:
      "platform.initStart": "initialize"
      "platform.initRuntimeDone": "ready"
      "platform.start": "start"
      "platform.runtimeDone": "finish"

  make: do ({ make } = {}) ->

    make = generic name: "LogEvent.make"
      
    # original AWS event
    generic make,
      ({ timestamp, message }) -> timestamp? && message?
      ({ message }) -> LogEvent.make JSON.parse message

    # system event
    generic make,
      ({ type }) -> type?
      ({ time, type, record }) ->
        {
          timestamp: time
          request: record.requestId
          type: "system"
          data: LogEvent.System.Dictionary[ type ] ? type
        }

    # application event
    generic make,
      ({ requestId }) -> requestId?
      ({ timestamp, requestId, level, message }) ->
        {
          timestamp
          request: requestId
          type: "application"
          level: Text.toLowerCase level
          data: message
        }

    # kaiko event
    generic make,
      ({ message }) -> message?.data?
      ({ timestamp, requestId, message }) ->
        {
          timestamp
          request: requestId
          type: "application"
          elapsed: message.timestamp
          context: message.context
          level: message.level
          data: message.data
        }

    make

Tasks =

  # WIP
  tail: ({ lambda }, name ) ->
    handler = if name?
      lambda.find ( specifier ) -> name == specifier.name
    else
      lambda[0]
    if handler?
      events = tail "/aws/lambda/#{ handler.name }"
      for await event from events
        console.log JSON.stringify LogEvent.make event

  deploy: ({ lambda }) ->
    Promise.all do ->
      for specifier in lambda
        Lambda.deploy specifier

  handlers: ({ lambda }) ->
    for specifier in lambda
      if specifier.generate?
        await Handlers.generateIndex specifier
    
      if specifier.generate? or specifier.verify?
        await Handlers.verify specifier

  version: ({ lambda }, pattern ) ->
    re = ///#{ pattern }///i
    handlers = lambda.filter ( handler ) -> re.test handler.name
    switch handlers.length
      when 1
        Lambda.version handlers[ 0 ].name
      when 0
        throw new Error "No match for pattern: [ #{ pattern } ]"
      else
        throw new Error "Ambiguous pattern: [ #{ pattern } ]"
  
  versionAll: ({ lambda }) ->
    Promise.all do ->
      for handler in lambda
        Lambda.version handler.name
  
  undeploy: ({ lambda }) ->
    Promise.all do ->
      for { name } in lambda
        Lambda.delete name          

export default Tasks