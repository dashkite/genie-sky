import FS from "node:fs/promises"
import Path from "node:path"
import * as Fn from "@dashkite/joy/function"
import * as Text from "@dashkite/joy/text"
import * as Pred from "@dashkite/joy/predicate"
import * as Value from "@dashkite/joy/value"
import * as Time from "@dashkite/joy/time"

import YAML from "js-yaml"

import { Name } from "@dashkite/name"
import { Mixins, getDRN } from "@dashkite/drn"
import { guard } from "./helpers"

import {
  publishLambda
  versionLambda
  deleteLambda
} from "@dashkite/dolores/lambda"

import { 
  getRoleARN
} from "@dashkite/dolores/roles"

updateLambdas = ({ namespace, lambda, version, context }) ->
  mode = process.env.mode ? "development"

  for handler in lambda?.handlers ? []
    
    try
      data = await FS.readFile ".sky/build/#{ handler.name }.zip"
    
    if data?

      console.log "uploading zip file", data.length

      name = await getDRN Name.getURI { type: "lambda", namespace, name: handler.name }
      role = await getRoleARN name

      config = { 
        handler.configuration...
        handler.configurations?.default...
        ( handler.configurations?[ mode ] )...
      }
      config.environment = { context, mode, config.environment... }

      # TODO get handler from config
      await publishLambda name, data, {
        handler: "index.handler"
        config...
        role
      }

      if version
        await versionLambda name

isHandler = Pred.all [
  Text.endsWith ".coffee"
  Pred.negate Value.eq  "index.coffee"
]

generateHandlerIndex = ({ generate }) ->
  imports = ""
  handlers = "handlers =\n"

  root = Path.resolve generate.path
  paths = await FS.readdir root

  for path in paths when isHandler path
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

verifyHandlers = ({ generate, verify }) ->

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

export default (genie, { namespace, lambda, mixins }) ->
  
  genie.define "sky:lambda:handlers", ->

    for handler in lambda.handlers
      if handler.generate?
        await generateHandlerIndex handler
    
      if handler.generate? or handler.verify?
        await verifyHandlers handler

  genie.define "sky:lambda:update",
    [ 
      "clean"
      "sky:roles:publish:*"
      "sky:lambda:handlers"
      "sky:zip:*" 
    ],
    guard (environment) ->
      updateLambdas {
        namespace
        environment
        lambda
        version: false 
      }

  genie.define "sky:lambda:publish",
    [ 
      "clean"
      "sky:roles:publish"
      "sky:lambda:handlers"
      "sky:zip" 
    ],
    ->
      context = JSON.stringify await Mixins.apply mixins, genie
      updateLambdas {
        namespace
        lambda
        version: true
        context
      }

  genie.define "sky:lambda:version", guard (environment, name) ->
    versionLambda "#{namespace}-#{environment}-#{name}"

  genie.define "sky:lambda:delete", ->
    for handler in lambda?.handlers ? []
      name = await getDRN Name.getURI { type: "lambda", namespace, name: handler.name }
      await deleteLambda name
