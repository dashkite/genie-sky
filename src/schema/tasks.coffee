import * as M from "@dashkite/masonry"
import YAML from "js-yaml"
import Ajv from "ajv/dist/2020"

fail = ( message ) -> throw new Error "sky-presets: #{ message }"

load = ( type ) ->
  switch type
    when "api" then import( "@dashkite/sky-api-description/schema" )
    when "policy" then import( "@dashkite/enchant/schema" )
    when "rune" then import( "@dashkite/runes/schema" )
    else fail "invalid schema type [ #{ type } ]"

_validate = ( type ) ->
  ({ input }) -> 
    ajv = new Ajv allowUnionTypes: true
    schema = await load type
    if ! ( ajv.validate schema, YAML.load input )
      for error in ajv.errors
        console.error "Error:", error.message
        console.error "       @", error.instancePath
      fail "validation failed"

validate = ({ glob, type }) ->
  M.start [
      M.glob glob, "."
      M.read
      M.tr _validate type
    ]

Tasks = 

  validate: ({ schema }) ->
    
    schema = if !( Array.isArray schema )
      [ schema ]
    else schema

    for { type, glob } in schema
      validate { glob, type }

export default Tasks


