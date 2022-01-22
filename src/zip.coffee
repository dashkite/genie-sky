import FS from "fs/promises"
import Path from "path"
import * as m from "@dashkite/masonry"
import { confidential } from "panda-confidential"
import Webpack from "webpack"

export default (genie) ->
  genie.define "sky:zip", (environment) ->
    environment = "development" if environment != "production"

    await do ->
      new Promise (resolve, reject) ->
        Webpack 
          mode: environment
          devtool: "inline-source-map"
          optimization:
            nodeEnv: environment
          target: "node"
          node:
            global: true
          entry:
            "index": Path.resolve "src/index.coffee"
          output:
            path: Path.resolve "build/lambda"
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

      # TODO apparently webpack returns before it's finished writing the file?
      loop
        try
          await FS.readFile "build/lambda/index.js"
          break

      await do m.exec "zip", [ "-qr", "-9", "build/lambda.zip", "build/lambda" ]
    

