import { generic } from "@dashkite/joy/generic"
import * as Type from "@dashkite/joy/type"
import * as Logger from "@dashkite/dolores/logger"
import resolve from "#helpers/resolve"

Logger.configure root: ".sky/log"

Preset =
  
  imported: []
  
  install: generic name: "install" 
  
  
generic Preset.install, Type.isString, ( name ) ->
  unless name in Preset.imported
    try
      installer = ( await import( "./#{ name }" ) ).default
      Preset.install installer
    catch error
      if error.code != "MODULE_NOT_FOUND"
        console.log error

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
