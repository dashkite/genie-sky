import { guard } from "./helpers"

import {
  getQueueURL
  putQueue
  emptyQueue
  deleteQueue
} from "@dashkite/dolores/queue"

export default ( genie, options ) ->
  if options.queues?
    { queues } = options

    genie.define "sky:queues:check", ->
      missing = []
      for queue in queues
        if !( await getQueueURL queue.name )
          missing.push queue.name
      if missing.length == 0
        console.log "All queues are available."
      else
        for name in missing
          console.warn "Queue [#{name}] does not exist or is unavailable"
        throw new Error "queues:check failed"

    genie.define "sky:queues:put", ->
      for queue in queues
        await putQueue queue.name

    genie.define "sky:queue:empty", guard (name) ->
      if await getQueueURL name
        await emptyQueue name
      else
        throw new Error "queue [#{name}] does not exist"

    genie.define "sky:queue:delete", guard (name) ->
      if await getQueueURL name
        await emptyQueue name
        await deleteQueue name
        console.log "Expect this operation to take another 60 seconds to complete."
      else
        throw new Error "queue [#{name}] does not exist"