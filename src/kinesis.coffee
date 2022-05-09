import YAML from "js-yaml"
import { guard } from "./helpers"

import {
  hasStream
  getStream
  putStream
  deleteStream
  listConsumers
} from "@dashkite/dolores/kinesis"


export default ( genie, options ) ->
  if options.kinesis?
    { kinesis } = options

    _putStream = (stream) ->
      await putStream stream.name

    _deleteStream = (name) ->
      await deleteStream name

    genie.define "sky:kinesis:streams:check", ->
      missing = []
      for stream in kinesis
        if !( await hasStream stream.name )
          missing.push stream.name
      if missing.length == 0
        console.log "All streams are available."
      else
        for name in missing
          console.warn "Stream [#{name}] does not exist or is unavailable"
        throw new Error "kinesis:streams:check failed"

    genie.define "sky:kinesis:streams:put", ->
      for stream in kinesis
        await _putStream stream

    genie.define "sky:kinesis:stream:put", guard (name) ->
      if ( stream = kinesis.find (b) -> b.name == name )?
        await _putStream stream
      else
        throw new Error "configuration is not available for stream [#{name}]"

    genie.define "sky:kinesis:stream:delete", guard (name) ->
      if await hasStream name
        await _deleteStream name
      else
        throw new Error "stream [#{name}] does not exist"

    genie.define "sky:kinesis:stream:get", guard (name) ->
      console.log await getStream name

    genie.define "sky:kinesis:stream:list-consumers", guard (name) ->
      if ( stream = await getStream name )?
        console.log YAML.dump await listConsumers stream
      else
        throw new Error "stream [#{name}] does not exist"
      