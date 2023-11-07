import * as Fn from "@dashkite/joy/function"
import { generic } from "@dashkite/joy/generic"
import * as Type from "@dashkite/joy/type"
import * as M from "@dashkite/masonry"
# import yaml from "@dashkite/masonry-yaml"
import YAML from "js-yaml"
import modularize from "@dashkite/masonry-export"
import T from "@dashkite/masonry-targets"
import W from "@dashkite/masonry-watch"
import * as DRN from "@dashkite/drn-sky"


defaults =
  targets:
    browser: [
      preset: "js"
      glob: [
        "src/**/*.yaml"
        "test/**/*.yaml"
      ]
    ]
    node: [
      preset: "js"
      glob: [
        "src/**/*.yaml"
        "test/**/*.yaml"
      ]
    ]

resolve = generic 
  name: "resolve"
  default: Fn.identity

generic resolve, Type.isString, ( text ) ->
  if text.startsWith "drn:"
    await DRN.resolve text
  else if text.startsWith "urn:drn:"
    text[7..]
  else text

generic resolve, Type.isObject, ( object ) ->
  result = {}
  for key, value of object
    result[ key ] = await resolve value
  result

generic resolve, Type.isArray, ( array ) ->
  Promise.all do ->
    for value in array
      resolve value

drn = ({ input }) -> resolve input

# TODO should masonry-yaml just produce an object?
yaml = ({ input }) -> YAML.load input

json = ({ input }) -> JSON.stringify input

Tasks =

  build: ( options ) ->
    options = { defaults..., options.yaml... }
    do M.start [
      T.glob options.targets
      M.read
      M.tr [ yaml, drn, json, modularize ]
      T.extension ".${ build.preset }"
      T.write "build/${ build.target }"
    ]

  watch: ( options ) ->
    options = { defaults..., options.yaml... }
    do M.start [
      W.glob options.targets
      W.match type: "file", name: [ "add", "change" ], [
        M.read
        M.tr yaml
        T.extension ".${ build.preset }"
        T.write "build/${ build.target }"
      ]
      W.match type: "file", name: "rm", [
        T.extension ".${ build.preset }"
        T.rm "build/${ build.target }"
      ]
      W.match type: "directory", name: "rm", 
        T.rm "build/${ build.target }"        
    ]

export default Tasks

