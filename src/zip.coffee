import FS from "fs/promises"
import * as m from "@dashkite/masonry"
import { confidential } from "panda-confidential"
import ChildProcess from "child_process"

Confidential = confidential()

hash = (text) ->
  message = Confidential.Message.from "utf8", text
  Confidential
    .hash message
    .to "base36"

exec = (command) ->
  new Promise (resolve, reject) ->
    ChildProcess.exec command, (error, stdout, stderr) ->
      if error?
        reject error
      else
        resolve stdout

export default (genie) ->

  genie.define "zip", [ "build" ], ->
    await FS.mkdir "build/lambda/src", recursive: true
    await FS.cp "build/node/src", "build/lambda/src", recursive: true
    await FS.cp "package.json", "build/lambda/package.json"
    cwd = process.cwd()
    process.chdir "build/lambda"
    await do m.exec "npm", [ "install", "--production" ]
    process.chdir cwd
    await do m.exec "zip", [ "-qr", "build/lambda.zip", "build/lambda" ]
    

