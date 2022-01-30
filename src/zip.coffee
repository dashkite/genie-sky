import FS from "fs/promises"
import Path from "path"
import * as m from "@dashkite/masonry"
import { confidential } from "panda-confidential"
import Webpack from "webpack"

bundle = ( { environment, name, path } ) ->
  new Promise (resolve, reject) ->
    Webpack 
      mode: environment
      devtool: if environment != "production" then "inline-source-map"
      optimization:
        nodeEnv: environment
      target: "node"
      node:
        global: true
      entry:
        index: Path.resolve path
      output:
        path: Path.resolve "build/lambda/#{ name }"
        filename: "[name].js"
        library: 
          type: "commonjs2"
      module:
        rules: [
          test: /\.coffee$/
          use: [ require.resolve "coffee-loader" ]
        ,
          test: /.yaml$/
          type: "json"
          loader: require.resolve "yaml-loader"
        ,
          test: /.pug$/
          use: [ require.resolve "pug-loader" ]
        ,
          test: /.styl$/
          use: [
            require.resolve "raw-loader"
            require.resolve "stylus-loader"
          ]
        ]
      resolve:
        extensions: [ ".js", ".json", ".yaml", ".coffee" ]
        modules: [ "node_modules" ]
      (error, result) ->
        if error? || result.hasErrors()
          console.error result?.toString colors: true
          reject error
        else
          resolve result

export default (genie, { lambda }) ->
  genie.define "sky:zip", (environment) ->
    environment = "development" if environment != "production"
    for handler in lambda.handlers
      result = await bundle { environment, handler... }

      # TODO compare to saved hashes and skip zip/upload when they're the same

      
      # TODO apparently webpack returns before it's finished writing the file?
      loop
        try
          await FS.readFile "build/lambda/#{ handler.name }/index.js"
          break

      await do m.exec "zip", [
        "-qr"
        "-9"
        "build/lambda/#{ handler.name }.zip"
        "build/lambda/#{ handler.name }"
      ]
  

