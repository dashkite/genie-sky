import * as M from "@dashkite/masonry"
import YAML from "js-yaml"
import Ajv from "ajv/dist/2020"
import apiSchema from "@dashkite/sky-api-description/schema"
import policySchema from "@dashkite/enchant/schema"
import runeSchema from "@dashkite/runes/schema"

ajv = new Ajv allowUnionTypes: true

validate = ( schema ) ->
  ({ input }) -> 
    if ! (ajv.validate schema, YAML.load input)
      for error in ajv.errors
        console.error "Error:", error.message
        console.error "       @", error.instancePath

export default (t, { schema }) ->
  { type, glob, auto } = schema

  t.define "sky:schema:api:validate", M.start [
    M.glob glob, "."
    M.read
    M.tr validate apiSchema
  ]

  t.define "sky:schema:policy:validate", M.start [
    M.glob glob, "."
    M.read
    M.tr validate policySchema
  ]

  t.define "sky:schema:rune:validate", M.start [
    M.glob glob, "."
    M.read
    M.tr validate runeSchema
  ]

  auto ?= true
  if auto
    switch type
      when "api"
        t.before "build", "sky:schema:api:validate"
      when "policy"
        t.before "build", "sky:schema:policy:validate"
      when "rune"
        t.before "build", "sky:schema:rune:validate"


