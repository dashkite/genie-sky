import FS from "node:fs/promises"
import { generic } from "@dashkite/joy/generic"
import * as Type from "@dashkite/joy/type"
import * as Logger from "@dashkite/dolores/logger"
import resolve from "#helpers/resolve"

Logger.configure root: ".sky/log"

exist = ( path ) ->
  try 
    await FS.readFile path
    true
  catch 
    false

Preset =
  
  imported: []
  
  install: generic name: "install" 

generic Preset.install, Type.isString, ( name ) ->
  unless name in Preset.imported
    paths = [
      "#{ __dirname }/#{ name }/index.js"
      "#{ __dirname }/#{ name }.js"
    ]
    for path in paths   
      if await exist path
        installer = ( require path ).default
        Preset.install installer
        break

generic Preset.install, Type.isObject, ( installer ) ->
  Promise.all [
    Preset.install installer.import
    Preset.install installer.install
  ]

generic Preset.install, Type.isArray, ( installers ) ->
  Promise.all do ->
    for installer in installers
      Preset.install installer
      
export default ( genie ) ->
  
  if ( options = genie.get "sky" )?

    options = await resolve options

    generic Preset.install, Type.isFunction, ( install ) ->
      install genie, options
    
    Promise.all [
      Preset.install [ "clean", "env" ]
      Preset.install ( Object.keys options )
    ]
