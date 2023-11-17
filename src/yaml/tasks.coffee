import * as M from "@dashkite/masonry"
# import yaml from "@dashkite/masonry-yaml"
import YAML from "js-yaml"
import modularize from "@dashkite/masonry-export"
import T from "@dashkite/masonry-targets"
import resolve from "#helpers/resolve"

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
    W = await import("@dashkite/masonry-watch")
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

