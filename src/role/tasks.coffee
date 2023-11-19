import * as Fn from "@dashkite/joy/function"
import { generic } from "@dashkite/joy/generic"
import * as Type from "@dashkite/joy/type"
import * as DRN from "@dashkite/drn-sky"
import { 
  createRole
} from "@dashkite/dolores/roles"
import Builders from "./builders"

Mixin =

  # resolve a DRN URN into an object that we
  # can use to build a policy statement
  resolve: do ({ resolve } = {}) ->

    resolve = generic name: "resolve"

    generic resolve, Type.isString, ( urn ) ->
      if urn.startsWith "urn:drn:"
        drn = DRN.from urn
        specifier: DRN.decode drn
        name: await DRN.resolve drn
      else
        throw new Error "Invalid mixin URN: [ #{ drn } ]"

    generic resolve, Type.isObject, Fn.identity

    resolve

Policy =

  # build a policy from a list of mixins
  build: ({ name, url, mixins }) ->

    mixins ?= []
    
    # automatic mixins
    mixins.push {
      name
      specifier:
        type: "cloudwatch"
    }

    policies = []
    
    for mixin in mixins
      { name, specifier } = if Type.isString mixin
        await Mixin.resolve mixin                
      else mixin
      if ( builder = Builders[ specifier.type ] )?
        statements = await builder { 
          mixin...
          name
          specifier...
        }
        policies.push statements...
      else
        throw new Error "Unknown type for mixin [ #{ name } ]"
    
    policies

Tasks =

  deploy: ( options ) ->
    Promise.all await do ->
      for specifier in options.lambda
        createRole specifier.name,
          ( await Policy.build specifier ), 
          options[ "managed-policies" ]

  undeploy: ({ lambda }) ->
    for specifier in lambda
      deleteRole specifier.name

export default Tasks

