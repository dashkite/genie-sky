import FS from "fs/promises"
import * as m from "@dashkite/masonry"

export default (genie) ->

  console.log "hello from sky-presets! :)"

  genie.define "zip", [ "build" ], ->
    await FS.mkdir "build/lambda/src", recursive: true
    await FS.cp "build/node/src", "build/lambda/src", recursive: true
    await FS.cp "package.json", "build/lambda/package.json"
    cwd = process.cwd()
    process.chdir "build/lambda"
    await do m.exec "npm", [ "install", "--production" ]
    process.chdir cwd
    await do m.exec "zip", [ "-qr", "build/lambda.zip", "build/lambda" ]
    

